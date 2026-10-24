module network

import compress.deflate
import encoding.base64
import sync
import time
import x.json2
import bedrock_v.protocol
import bedrock_v.protocol.packets
import bedrock_v.protocol.serializer

struct ScriptWire {
mut:
	inbound  [][]u8
	next     int
	outbound [][]u8
	closed   bool
}

fn (mut w ScriptWire) read_message() ![]u8 {
	if w.next >= w.inbound.len {
		return error('the client sent nothing more')
	}
	b := w.inbound[w.next]
	w.next++
	return b
}

fn (mut w ScriptWire) write_message(b []u8) ! {
	w.outbound << b
}

fn (mut w ScriptWire) remote() string {
	return 'script'
}

fn (mut w ScriptWire) close() {
	w.closed = true
}

fn client_message(ps []protocol.Packet, compression bool) []u8 {
	mut encoded := [][]u8{}
	for p in ps {
		encoded << protocol.encode_packet_to_bytes(p)
	}
	return encode_batch(encoded, compression, default_compression_threshold) or { panic(err) }
}

fn sent(w &ScriptWire, n int, compression bool) []protocol.Packet {
	pool := protocol.new_pool()
	batch := decode_batch(w.outbound[n], compression) or { panic(err) }
	mut ps := []protocol.Packet{}
	for b in batch {
		mut r := serializer.new_reader(b)
		ps << pool.decode(mut r) or { panic(err) }
	}
	return ps
}

fn login_request(name string, xuid string) []u8 {
	payload := json2.encode({
		'extraData':         json2.Any(json2.Any({
			'displayName': json2.Any(name)
			'XUID':        json2.Any(xuid)
			'identity':    json2.Any('00000000-0000-0000-0000-000000000001')
		}))
		'identityPublicKey': json2.Any('CLIENTKEY')
	})
	token := '${base64.url_encode('{"alg":"ES384"}'.bytes())}.${base64.url_encode(payload.bytes())}.signature'
	chain := json2.encode({
		'chain': json2.Any([json2.Any(token)])
	})
	mut w := serializer.new_writer()
	w.le_u32(u32(chain.len))
	w.write_raw(chain.bytes())
	return w.bytes()
}

fn request_settings(version int) protocol.Packet {
	return &packets.RequestNetworkSettingsPacket{
		client_network_version: i32(version)
	}
}

fn logging_in_client(name string) &ScriptWire {
	return &ScriptWire{
		inbound: [
			client_message([request_settings(protocol.protocol_id)], false),
			client_message([
				protocol.Packet(&packets.LoginPacket{
					client_network_version: i32(protocol.protocol_id)
					connection_request:     login_request(name, '2535000000000000')
				}),
			], true),
			client_message([
				protocol.Packet(&packets.ClientCacheStatusPacket{
					is_cache_supported: false
				}),
				protocol.Packet(&packets.ResourcePackClientResponsePacket{
					response: packets.ResourcePackResponseDownloadingFinished{}
				}),
				protocol.Packet(&packets.ResourcePackClientResponsePacket{
					response: packets.ResourcePackResponseStackFinished{}
				}),
			], true),
		]
	}
}

fn test_a_batch_round_trips_compressed_and_uncompressed() {
	packets_out := ['hello'.bytes(), 'a longer packet body'.bytes()]
	for compression in [true, false] {
		framed := encode_batch(packets_out, compression, 0) or { panic(err) }
		assert decode_batch(framed, compression) or { panic(err) } == packets_out
	}
}

fn test_a_short_batch_is_marked_uncompressed() {
	framed := encode_batch([[]u8('tiny'.bytes())], true, default_compression_threshold) or {
		panic(err)
	}
	assert framed[0] == compression_none
	assert decode_batch(framed, true) or { panic(err) } == [[]u8('tiny'.bytes())]
}

fn test_an_oversized_packet_length_is_refused() {
	mut w := serializer.new_writer()
	w.write_varuint32(u32(max_single_packet + 1))
	w.write_raw('short'.bytes())
	if _ := decode_batch(w.bytes(), false) {
		assert false, 'an oversized packet length was accepted'
	}
}

fn test_an_unknown_compression_algorithm_is_refused() {
	mut framed := [u8(0x7f)]
	framed << 'body'.bytes()
	if _ := decode_batch(framed, true) {
		assert false, 'an unknown compression algorithm was accepted'
	}
}

fn test_a_client_logs_in_and_both_ends_compress() {
	mut w := logging_in_client('Scher')
	mut c := new_conn(mut w)
	identity := handshake(mut c, LoginConfig{}) or { panic(err) }

	assert identity.display_name == 'Scher'
	assert identity.xuid == '2535000000000000'
	assert !identity.xbox_authenticated

	assert sent(w, 0, false)[0] is packets.NetworkSettingsPacket
	status := sent(w, 1, true)[0]
	assert status is packets.PlayStatusPacket
	if status is packets.PlayStatusPacket {
		assert status.status == .login_success
	}
	assert sent(w, 2, true)[0] is packets.ResourcePacksInfoPacket
	assert sent(w, 3, true)[0] is packets.ResourcePackStackPacket
	assert w.outbound.len == 4
}

fn test_a_client_on_another_protocol_version_is_refused() {
	mut w := &ScriptWire{
		inbound: [client_message([request_settings(protocol.protocol_id - 1)], false)]
	}
	mut c := new_conn(mut w)
	if _ := handshake(mut c, LoginConfig{}) {
		assert false, 'a client on the wrong protocol version logged in'
	} else {
		assert err is VersionMismatch, 'the refusal does not say it was the version: ${err}'
	}
	status := sent(w, 0, false)[0]
	assert status is packets.PlayStatusPacket
	if status is packets.PlayStatusPacket {
		assert status.status == .login_failed_client_old
	}
}

fn test_a_client_that_will_not_finish_logging_in_is_refused() {
	mut inbound := [][]u8{}
	for _ in 0 .. 200 {
		inbound << client_message([request_settings(protocol.protocol_id)], false)
	}
	mut w := &ScriptWire{
		inbound: inbound
	}
	mut c := new_conn(mut w)
	if _ := handshake(mut c, LoginConfig{}) {
		assert false, 'a client that never logged in got through the handshake'
	}
	assert w.next < w.inbound.len
}

fn test_a_client_refusing_required_packs_is_refused() {
	mut w := logging_in_client('Scher')
	w.inbound[2] = client_message([
		protocol.Packet(&packets.ResourcePackClientResponsePacket{
			response: packets.ResourcePackResponseCancel{}
		}),
	], true)
	mut c := new_conn(mut w)
	if _ := handshake(mut c, LoginConfig{ packs_required: true }) {
		assert false, 'a client that refused required packs logged in'
	}
}

fn test_an_unknown_packet_is_skipped() {
	mut unknown := serializer.new_writer()
	protocol.write_packet_header(mut unknown, 0xfe, 0, 0)
	mut w := &ScriptWire{
		inbound: [
			encode_batch([unknown.bytes()], false, 0) or { panic(err) },
			client_message([request_settings(protocol.protocol_id)], false),
		]
	}
	mut c := new_conn(mut w)
	p := c.read() or { panic(err) }
	assert p is packets.RequestNetworkSettingsPacket
	assert c.dropped() == 1
}

fn test_an_unexpected_packet_does_not_stop_the_login() {
	mut w := logging_in_client('Scher')
	radius := client_message([
		protocol.Packet(&packets.RequestChunkRadiusPacket{
			chunk_radius: 8
		}),
	], true)
	w.inbound.insert(2, radius)
	mut c := new_conn(mut w)
	identity := handshake(mut c, LoginConfig{}) or { panic(err) }
	assert identity.display_name == 'Scher'
}

fn test_a_batch_that_expands_past_the_limit_is_refused() {
	bomb := deflate.compress_raw([]u8{len: max_decompressed_batch + 1024}) or { panic(err) }
	assert bomb.len < 64 * 1024, 'the test needs a frame far smaller than what it expands to'
	mut framed := [compression_flate]
	framed << bomb
	if _ := decode_batch(framed, true) {
		assert false, 'a batch that expands past the limit was accepted'
	} else {
		assert err.msg().contains('limit'), 'refused for another reason: ${err}'
	}
}

// JunkWire sends batches that decode to nothing for as long as it is read.
struct JunkWire {
mut:
	sent int
}

fn (mut w JunkWire) read_message() ![]u8 {
	w.sent++
	mut unknown := serializer.new_writer()
	protocol.write_packet_header(mut unknown, 0xfe, 0, 0)
	return encode_batch([unknown.bytes()], false, 0)!
}

fn (mut w JunkWire) write_message(b []u8) ! {}

fn (mut w JunkWire) remote() string {
	return 'junk'
}

fn (mut w JunkWire) close() {}

fn test_a_read_gives_up_on_messages_that_carry_no_packet() {
	mut w := &JunkWire{}
	mut c := new_conn(mut w)
	if _ := c.read() {
		assert false, 'a read returned a packet out of messages that had none'
	}
	assert w.sent == max_empty_reads + 1, 'the read did not stop at the limit'
}

fn junk_batch() []u8 {
	mut unknown := serializer.new_writer()
	protocol.write_packet_header(mut unknown, 0xfe, 0, 0)
	return encode_batch([unknown.bytes()], false, 0) or { panic(err) }
}

fn test_messages_that_carry_no_packet_still_spend_the_login_budget() {
	mut junk := [][]u8{}
	for _ in 0 .. 10 {
		junk << junk_batch()
	}
	mut w := logging_in_client('Scher')
	w.inbound.prepend(junk)
	mut c := new_conn(mut w)
	if _ := handshake(mut c, LoginConfig{ max_login_messages: 8 }) {
		assert false, 'a client logged in on a budget its junk should have spent'
	} else {
		assert err.msg().contains('messages'), 'refused for another reason: ${err}'
	}
}

fn test_a_login_survives_junk_within_the_budget() {
	mut junk := [][]u8{}
	for _ in 0 .. 10 {
		junk << junk_batch()
	}
	mut w := logging_in_client('Scher')
	w.inbound.prepend(junk)
	mut c := new_conn(mut w)
	identity := handshake(mut c, LoginConfig{}) or { panic(err) }
	assert identity.display_name == 'Scher'
}

// BlockingWire is a client that connects and then says nothing.
struct BlockingWire {
mut:
	unblock chan bool   = chan bool{}
	guard   &sync.Mutex = sync.new_mutex()
	reading bool
	closed  bool
}

fn (mut w BlockingWire) read_message() ![]u8 {
	w.guard.lock()
	w.reading = true
	w.guard.unlock()
	_ := <-w.unblock or { return error('the connection was closed') }
	return error('the connection was closed')
}

fn (mut w BlockingWire) write_message(b []u8) ! {
	if w.is_closed() {
		return error('the connection was closed')
	}
}

fn (mut w BlockingWire) remote() string {
	return 'blocking'
}

fn (mut w BlockingWire) close() {
	w.guard.lock()
	defer {
		w.guard.unlock()
	}
	if w.closed {
		return
	}
	w.closed = true
	w.unblock.close()
}

fn (mut w BlockingWire) is_closed() bool {
	w.guard.lock()
	defer {
		w.guard.unlock()
	}
	return w.closed
}

fn (mut w BlockingWire) is_reading() bool {
	w.guard.lock()
	defer {
		w.guard.unlock()
	}
	return w.reading
}

// WiresListener hands out the wires it was given, one per accept.
struct WiresListener {
mut:
	wires []Wire
	next  int
}

fn (mut l WiresListener) accept(timeout time.Duration) !Wire {
	if l.next >= l.wires.len {
		time.sleep(5 * time.millisecond)
		return error('no client arrived')
	}
	l.next++
	return l.wires[l.next - 1]
}

fn (mut l WiresListener) announce(online int) {}

fn (l &WiresListener) addr() string {
	return 'wires'
}

fn (mut l WiresListener) close() {}

fn logins_from(wires []Wire, max_players int, cfg LoginConfig) (&LoginHandler, &ListenerContext) {
	mut ctx := &ListenerContext{
		status: Status{
			max_players: max_players
		}
	}
	h := LoginHandler.new(&WiresListener{
		wires: wires
	}, mut ctx, cfg)
	return h, ctx
}

fn reading(wires []&BlockingWire) int {
	mut n := 0
	for w in wires {
		mut wire := unsafe { w }
		if wire.is_reading() {
			n++
		}
	}
	return n
}

fn closed(wires []&BlockingWire) int {
	mut n := 0
	for w in wires {
		mut wire := unsafe { w }
		if wire.is_closed() {
			n++
		}
	}
	return n
}

fn test_a_client_that_logs_in_is_handed_over_holding_its_slot() {
	mut w := logging_in_client('Scher')
	mut h, mut ctx := logins_from([Wire(w)], 20, LoginConfig{})
	defer {
		h.close()
	}
	client := h.accept(5 * time.second) or { panic(err) }
	assert client.identity.display_name == 'Scher'
	assert ctx.player_count() == 1, 'the client gave its slot back on the way in'
}

fn test_only_so_many_clients_may_be_logging_in_at_once() {
	mut wires := []&BlockingWire{}
	mut given := []Wire{}
	for _ in 0 .. 6 {
		wire := &BlockingWire{}
		wires << wire
		given << wire
	}
	mut h, mut ctx := logins_from(given, 2, LoginConfig{})
	mut settled := 0
	for _ in 0 .. 400 {
		settled = reading(wires)
		if settled + closed(wires) == wires.len {
			break
		}
		time.sleep(5 * time.millisecond)
	}
	assert settled == 2, 'the server took ${settled} logins at once'
	assert closed(wires) == 4, 'the clients over the limit were not refused'
	assert ctx.player_count() == 2
	h.close()
	assert closed(wires) == wires.len, 'close left a login open'
	assert ctx.player_count() == 0, 'close kept the slots of the logins it ended'
}

fn test_a_client_that_never_finishes_logging_in_is_dropped() {
	mut wire := &BlockingWire{}
	mut h, mut ctx := logins_from([Wire(wire)], 20, LoginConfig{
		timeout: 50 * time.millisecond
	})
	defer {
		h.close()
	}
	for _ in 0 .. 400 {
		if wire.is_closed() && ctx.player_count() == 0 {
			break
		}
		time.sleep(5 * time.millisecond)
	}
	assert wire.is_closed(), 'a client that never logged in was left connected'
	assert ctx.player_count() == 0, 'a client dropped at the deadline kept its slot'
	if _ := h.accept(100 * time.millisecond) {
		assert false, 'a client that ran out of time was handed over'
	}
}

fn test_a_failed_login_gives_its_slot_back() {
	mut w := &ScriptWire{
		inbound: [client_message([request_settings(protocol.protocol_id - 1)], false)]
	}
	mut h, mut ctx := logins_from([Wire(w)], 20, LoginConfig{})
	defer {
		h.close()
	}
	for _ in 0 .. 400 {
		if w.closed {
			break
		}
		time.sleep(5 * time.millisecond)
	}
	for _ in 0 .. 400 {
		if ctx.player_count() == 0 {
			break
		}
		time.sleep(5 * time.millisecond)
	}
	assert w.closed, 'a client that failed to log in was left connected'
	assert ctx.player_count() == 0, 'a failed login kept its slot'
}
