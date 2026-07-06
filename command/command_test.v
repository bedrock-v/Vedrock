module command

import protocol
import protocol.types
import protocol.serializer
import language
import permission

fn base_ctx() Context {
	lang := language.load('en') or { panic('failed to load lang for test: ${err}') }
	return Context{
		lang:         lang
		sender_name:  'Steve'
		player_count: 3
		max_players:  20
		server_motd:  'Vedrock Server'
	}
}

struct RecordingSender {
mut:
	messages []string
	gamemode int = -1
	perm     permission.Permissible
	peers    map[string]Sender
}

fn (mut s RecordingSender) send_message(message string) ! {
	s.messages << message
}

fn (mut s RecordingSender) send_translation(key string, parameters []string) ! {
	s.messages << '${key} ${parameters}'
}

fn (mut s RecordingSender) set_gamemode(mode int) {
	s.gamemode = mode
}

fn (s &RecordingSender) has_permission(name string) bool {
	return s.perm.has_permission(name)
}

fn (mut s RecordingSender) find_player(name string) ?Sender {
	return s.peers[name.to_lower()] or { none }
}

fn test_version_command() {
	r := new_registry()
	mut sender := RecordingSender{}
	r.dispatch('/version', mut sender, base_ctx())!
	assert sender.messages.len == 1
	assert sender.messages[0].contains('Vedrock')
	assert sender.messages[0].contains('1.26.30')
	assert sender.messages[0].contains('1001')
}

fn test_version_alias() {
	r := new_registry()
	mut sender := RecordingSender{}
	r.dispatch('/ver', mut sender, base_ctx())!
	assert sender.messages[0].contains('Vedrock')
}

fn test_status_command() {
	r := new_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('status', mut sender, base_ctx())!
	assert sender.messages[0].contains('3')
	assert sender.messages[0].contains('20')
	assert sender.messages[0].contains('Vedrock Server')
}

fn test_status_command_denied_without_op() {
	r := new_registry()
	mut sender := RecordingSender{}
	r.dispatch('status', mut sender, base_ctx())!
	assert sender.messages[0].contains('permission')
}

fn test_unknown_command() {
	r := new_registry()
	mut sender := RecordingSender{}
	r.dispatch('/nope', mut sender, base_ctx())!
	assert sender.messages[0].contains('Unknown command')
}

fn test_gamemode_command() {
	r := new_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/gamemode creative', mut sender, base_ctx())!
	assert sender.gamemode == protocol.game_type_creative
	assert sender.messages[0].contains('commands.gamemode.success.self')
}

fn test_gamemode_command_usage_is_not_a_client_translation_key() {
	r := new_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/gamemode', mut sender, base_ctx())!
	assert sender.gamemode == -1
	assert sender.messages[0].contains('Usage')
	assert !sender.messages[0].contains('commands.gamemode.usage')
}

fn test_gamemode_command_denied_without_op() {
	r := new_registry()
	mut sender := RecordingSender{}
	r.dispatch('/gamemode creative', mut sender, base_ctx())!
	assert sender.gamemode == -1
	assert sender.messages[0].contains('permission')
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
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	pkt := r.available_commands(sender)
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

fn test_available_commands_filtered() {
	r := new_registry()
	sender := RecordingSender{}
	pkt := r.available_commands(sender)
	assert pkt.commands.len == 1
	assert pkt.commands[0].name == 'version'
}
