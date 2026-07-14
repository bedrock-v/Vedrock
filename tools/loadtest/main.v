module main

import os
import time
import sync
import sync.stdatomic
import raknet
import protocol
import protocol.types
import server.internal.network
import server.internal.logger

// LoadTest drives N concurrent RakNet clients through the Bedrock handshake
// against a running Vedrock server and reports connection/tick behaviour. It
// reuses the server's own network.Session transport so the framing, batching
// and flate compression match exactly what the server expects on the wire.
struct Config {
mut:
	host        string
	port        int
	connections int
	seconds     int
	send_login  bool
}

// Stats is the shared, atomically-updated result tally. Every worker thread
// mutates the same instance so the sums are already global when we print them.
struct Stats {
mut:
	dial_ok        &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	dial_fail      &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	handshake_ok   &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	handshake_fail &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	login_ok       &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	keepalives     &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	bytes_sent     &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	errors         &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
}

const dial_timeout = 8 * time.second
const settings_read_timeout = 5 * time.second
const keepalive_interval = 500 * time.millisecond

fn main() {
	cfg := parse_args() or {
		eprintln('error: ${err}')
		print_usage()
		exit(1)
	}
	run(cfg)
}

fn print_usage() {
	eprintln('usage: v run tools/loadtest/main.v <host> <port> <connections> <seconds> [--login]')
	eprintln('  host         server address (default 127.0.0.1)')
	eprintln('  port         server udp port (default 19132)')
	eprintln('  connections  concurrent clients to open (default 50)')
	eprintln('  seconds      hold duration in seconds (default 10)')
	eprintln('  --login      also send a Login packet to push the server into auth')
}

fn parse_args() !Config {
	args := os.args[1..]
	mut positional := []string{}
	mut send_login := false
	for a in args {
		if a == '--login' {
			send_login = true
		} else if a == '-h' || a == '--help' {
			print_usage()
			exit(0)
		} else {
			positional << a
		}
	}
	mut cfg := Config{
		host:        '127.0.0.1'
		port:        19132
		connections: 50
		seconds:     10
		send_login:  send_login
	}
	if positional.len > 0 {
		cfg.host = positional[0]
	}
	if positional.len > 1 {
		cfg.port = positional[1].int()
	}
	if positional.len > 2 {
		cfg.connections = positional[2].int()
	}
	if positional.len > 3 {
		cfg.seconds = positional[3].int()
	}
	if cfg.connections <= 0 {
		return error('connections must be > 0')
	}
	if cfg.seconds <= 0 {
		return error('seconds must be > 0')
	}
	return cfg
}

fn run(cfg Config) {
	address := '${cfg.host}:${cfg.port}'
	println('Vedrock loadtest -> ${address}')
	println('  connections=${cfg.connections} duration=${cfg.seconds}s login=${cfg.send_login}')

	// Silent logger - the transport wants one but we don't want per-packet noise.
	log := logger.new(.error)
	mut stats := &Stats{}
	// deadline is shared so every worker stops holding at the same wall-clock moment.
	deadline := time.now().add(cfg.seconds * time.second)

	mut wg := sync.new_waitgroup()
	wg.add(cfg.connections)
	start := time.now()
	for i in 0 .. cfg.connections {
		spawn worker(address, cfg, deadline, mut stats, log, mut wg)
		_ := i
	}
	wg.wait()
	elapsed := (time.now() - start).seconds()

	report(cfg, mut stats, elapsed)
}

// worker owns one client for the whole run: dial, handshake, then hold and
// keepalive until the shared deadline. Every failure is counted and the worker
// returns cleanly so one bad connection never stalls the batch.
fn worker(address string, cfg Config, deadline time.Time, mut stats Stats, log &logger.Logger, mut wg sync.WaitGroup) {
	defer {
		wg.done()
	}
	mut conn := raknet.dial_timeout(address, dial_timeout) or {
		stats.dial_fail.add(1)
		stats.errors.add(1)
		return
	}
	stats.dial_ok.add(1)
	mut transport := network.new_session(mut conn, log)
	defer {
		transport.close()
	}

	do_handshake(mut transport, cfg, mut stats) or {
		stats.handshake_fail.add(1)
		return
	}
	stats.handshake_ok.add(1)

	// Hold the connection open, trickling movement packets so the server keeps
	// doing per-connection read work for the whole duration.
	for time.now() < deadline {
		transport.send(keepalive_packet()) or { break }
		stats.keepalives.add(1)
		stats.bytes_sent.add(u64(keepalive_size))
		remaining := deadline - time.now()
		sleep := if remaining < keepalive_interval { remaining } else { keepalive_interval }
		if sleep > 0 {
			time.sleep(sleep)
		}
	}
}

// do_handshake sends RequestNetworkSettings, waits for NetworkSettings, enables
// compression, and optionally sends a Login. Reaching NetworkSettings is the
// success boundary - it proves the server ran the real per-connection protocol
// path (version check + settings response) for this client.
fn do_handshake(mut transport network.Session, cfg Config, mut stats Stats) ! {
	transport.send(&protocol.RequestNetworkSettingsPacket{
		protocol_version: protocol.current_protocol
	})!
	stats.bytes_sent.add(u64(request_settings_size))

	got_settings := wait_for_settings(mut transport) or { return err }
	if !got_settings {
		return error('no network settings')
	}
	transport.enable_compression(network.default_compression_threshold)

	if cfg.send_login {
		// An offline/garbage chain - the server will reject it at auth, but only
		// after doing the real login-stage work we want to exercise.
		transport.send(&protocol.LoginPacket{
			protocol:        protocol.current_protocol
			auth_info_json:  '{"chain":[]}'
			client_data_jwt: ''
		}) or {}
		stats.login_ok.add(1)
	}
}

// wait_for_settings reads batches until a NetworkSettings packet arrives or the
// read times out. read() blocks on the RakNet conn, whose read timeout the
// dialer already configured, so a stalled server surfaces as a read error.
fn wait_for_settings(mut transport network.Session) !bool {
	start := time.now()
	for time.now() - start < settings_read_timeout {
		packets := transport.read()!
		for p in packets {
			if p is protocol.NetworkSettingsPacket {
				return true
			}
		}
	}
	return false
}

const keepalive_size = 16
const request_settings_size = 12

// keepalive_packet is a cheap movement packet held constant across sends. The
// server decodes it as real inbound traffic even before spawn.
fn keepalive_packet() &protocol.PlayerAuthInputPacket {
	return &protocol.PlayerAuthInputPacket{
		pitch:    0.0
		yaw:      0.0
		position: types.Vector3{
			x: 0.0
			y: 64.0
			z: 0.0
		}
	}
}

fn report(cfg Config, mut stats Stats, elapsed f64) {
	dial_ok := stats.dial_ok.load()
	dial_fail := stats.dial_fail.load()
	hs_ok := stats.handshake_ok.load()
	hs_fail := stats.handshake_fail.load()
	login_ok := stats.login_ok.load()
	keepalives := stats.keepalives.load()
	bytes_sent := stats.bytes_sent.load()
	errors := stats.errors.load()

	conns_per_sec := if elapsed > 0 { f64(dial_ok) / elapsed } else { 0.0 }
	throughput_kb := if elapsed > 0 { (f64(bytes_sent) / 1024.0) / elapsed } else { 0.0 }

	println('')
	println('==================== loadtest results ====================')
	println('wall clock:            ${elapsed:.3f}s')
	println('target connections:    ${cfg.connections}')
	println('dial ok / fail:        ${dial_ok} / ${dial_fail}')
	println('handshake ok / fail:   ${hs_ok} / ${hs_fail}')
	if cfg.send_login {
		println('login packets sent:    ${login_ok}')
	}
	println('connections/sec:       ${conns_per_sec:.1f}')
	println('keepalives sent:       ${keepalives}')
	println('bytes sent (approx):   ${bytes_sent}')
	println('throughput:            ${throughput_kb:.1f} KB/s')
	println('errors:                ${errors}')
	println('==========================================================')
}
