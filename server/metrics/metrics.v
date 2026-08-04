module metrics

import compress.gzip
import net.http
import os
import rand
import runtime
import sync.stdatomic
import time
import server.internal.logger

// bstats_version is the payload format the submit endpoint expects.
pub const bstats_version = 1

const submit_url = 'https://bStats.org/submitData/server-implementation'
const submit_interval = 30 * time.minute
const shutdown_poll_interval = 500 * time.millisecond

// Config is the reporter's slice of the server configuration. server_uuid keeps
// one install recognisable across restarts.
pub struct Config {
pub mut:
	enabled             bool = true
	server_uuid         string
	log_failed_requests bool
}

@[heap]
pub struct Metrics {
	name string
	cfg  Config
	log  &logger.Logger
mut:
	charts  []Chart
	running &stdatomic.AtomicVal[bool] = stdatomic.new_atomic[bool](false)
}

pub fn new(name string, cfg Config, log &logger.Logger) &Metrics {
	return &Metrics{
		name: name
		cfg:  cfg
		log:  log.with_prefix('bStats')
	}
}

pub fn (mut m Metrics) add_chart(chart Chart) {
	m.charts << chart
}

pub fn (m &Metrics) enabled() bool {
	return m.cfg.enabled
}

// start kicks off submission on its own thread. Charts are collected there, so
// nothing here runs on the tick or actor threads.
pub fn (mut m Metrics) start() {
	if !m.cfg.enabled || m.running.load() {
		return
	}
	m.running.store(true)
	spawn m.submit_loop()
}

pub fn (mut m Metrics) stop() {
	m.running.store(false)
}

fn (mut m Metrics) submit_loop() {
	// bStats asks for a randomised start delay: servers tend to restart on the
	// hour, and without it every one of them would hit the backend at once.
	initial := 3 * time.minute + time.Duration(rand.i64n(i64(3 * time.minute)) or { 0 })
	if !m.wait(initial) {
		return
	}
	for {
		m.submit()
		if !m.wait(submit_interval) {
			return
		}
	}
}

// wait sleeps in slices so shutdown does not have to sit out a full interval.
// Returns false when metrics were stopped while waiting.
fn (mut m Metrics) wait(d time.Duration) bool {
	deadline := time.now().add(d)
	for time.now() < deadline {
		if !m.running.load() {
			return false
		}
		time.sleep(shutdown_poll_interval)
	}
	return m.running.load()
}

fn (mut m Metrics) submit() {
	send(m.payload()) or {
		if m.cfg.log_failed_requests {
			m.log.warn('Failed to submit metrics: ${err}')
		}
		return
	}
	m.log.debug('Submitted metrics')
}

// payload builds the bStats request body: host facts plus one entry per chart
// that produced data this cycle.
fn (m &Metrics) payload() string {
	mut charts := []string{cap: m.charts.len}
	for chart in m.charts {
		data := chart.data() or { continue }
		charts << '{"chartId":${json_string(chart.id())},"data":${data}}'
	}
	software := '{"pluginName":${json_string(m.name)},"customCharts":[${charts.join(',')}]}'
	host := os.uname()
	return
		'{"serverUUID":${json_string(m.cfg.server_uuid)},"osName":${json_string(host.sysname)},' +
		'"osArch":${json_string(host.machine)},"osVersion":${json_string(host.release)},' +
		'"coreCount":${runtime.nr_cpus()},"plugins":[${software}]}'
}

fn send(payload string) ! {
	compressed := gzip.compress(payload.bytes())!
	mut req := http.Request{
		method:     .post
		url:        submit_url
		data:       compressed.bytestr()
		user_agent: 'MC-Server/${bstats_version}'
	}
	req.add_custom_header('Accept', 'application/json')!
	req.add_custom_header('Connection', 'close')!
	req.add_custom_header('Content-Encoding', 'gzip')!
	req.add_header(.content_type, 'application/json')
	resp := req.do()!
	if resp.status_code >= 400 {
		return error('bStats responded with ${resp.status_code}')
	}
}

fn json_string(value string) string {
	mut out := '"'
	for c in value {
		match c {
			`"` { out += '\\"' }
			`\\` { out += '\\\\' }
			`\n` { out += '\\n' }
			`\r` { out += '\\r' }
			`\t` { out += '\\t' }
			else { out += if c < 0x20 { '' } else { c.ascii_str() } }
		}
	}
	return out + '"'
}
