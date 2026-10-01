module net

import encoding.base64
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

fn (mut w ScriptWire) encrypted() bool {
	return true
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
	assert identity.client_public_key == 'CLIENTKEY'
	// Nothing in an unverified chain is proof of who the player is.
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
