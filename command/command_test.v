module command

import protocol
import protocol.types
import protocol.serializer

fn base_ctx() Context {
	return Context{
		sender_name:  'Steve'
		player_count: 3
		max_players:  20
		server_motd:  'Vedrock Server'
	}
}

fn test_version_command() {
	r := new_registry()
	out := r.dispatch('/version', base_ctx())
	assert out.contains('Vedrock')
	assert out.contains('1.26.30')
	assert out.contains('1001')
}

fn test_version_alias() {
	r := new_registry()
	out := r.dispatch('/ver', base_ctx())
	assert out.contains('Vedrock')
}

fn test_status_command() {
	r := new_registry()
	out := r.dispatch('status', base_ctx())
	assert out.contains('3')
	assert out.contains('20')
	assert out.contains('Vedrock Server')
}

fn test_unknown_command() {
	r := new_registry()
	out := r.dispatch('/nope', base_ctx())
	assert out.contains('Unknown command')
}

fn test_resolve_missing() {
	r := new_registry()
	if _ := r.resolve('ghost') {
		assert false
	}
}

fn test_command_request_roundtrip() {
	pkt := protocol.CommandRequestPacket{
		command:     '/version'
		origin_data: types.CommandOriginData{
			type:       'player'
			request_id: 'req-1'
		}
		version:     '1'
	}
	encoded := protocol.encode_packet_to_bytes(&pkt)
	mut pool := protocol.new_packet_pool()
	mut reader := serializer.new_reader(encoded)
	decoded := pool.decode(mut reader)!
	assert decoded.name() == 'CommandRequestPacket'
	if decoded is protocol.CommandRequestPacket {
		assert decoded.command == '/version'
		assert decoded.origin_data.type == 'player'
		assert decoded.origin_data.request_id == 'req-1'
	} else {
		assert false
	}
}

fn test_available_commands_roundtrip() {
	r := new_registry()
	pkt := r.available_commands()
	assert pkt.commands.len == 3
	encoded := protocol.encode_packet_to_bytes(&pkt)
	mut pool := protocol.new_packet_pool()
	mut reader := serializer.new_reader(encoded)
	decoded := pool.decode(mut reader)!
	assert decoded.name() == 'AvailableCommandsPacket'
	if decoded is protocol.AvailableCommandsPacket {
		assert decoded.commands.len == 3
		assert decoded.commands[0].alias_enum_index == -1
		assert decoded.commands[0].overloads.len == 1
	} else {
		assert false
	}
}
