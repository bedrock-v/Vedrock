module default

import bedrock_v.protocol
import bedrock_v.protocol.serializer
import bedrock_v.protocol.types
import server.internal.language
import server.permission
import server.form
import server.cmd
import server.player
import server.player.bossbar
import server.player.scoreboard
import server.player.title
import bedrock_v.protocol.current as proto

fn full_registry() cmd.Registry {
	mut r := cmd.new_registry()
	register_all(mut r)
	return r
}

fn base_ctx() cmd.Context {
	lang := language.load('en') or { panic('failed to load lang for test: ${err}') }
	return cmd.Context{
		lang:         lang
		sender_name:  'Steve'
		player_count: 3
		max_players:  20
		server_motd:  'Vedrock Server'
	}
}

struct RecordingSender {
mut:
	messages                []string
	broadcasts              []string
	gamemode                ?player.Gamemode
	perm                    permission.Permissible
	peers                   map[string]cmd.Sender
	sender_name             string = 'Steve'
	killed                  bool
	disconnected            bool
	disconnect_msg          string
	pos_x                   f32
	pos_y                   f32
	pos_z                   f32
	cleared                 bool
	given_id                string
	given_experience        int
	given_experience_levels int
	given_count             int
	given_ok                bool = true
	whitelisted             []string
	whitelist_on            bool
	difficulty_value        int
	shown_title             string
	broadcast_titles        []string
	is_player_val           bool = true
	sent_form               ?form.Form
	worlds                  []string
	unloaded_worlds         []string
	created_dim             string
	created_gen             string
	tp_world                string
	bossbar_text            string
	scoreboard_title        string
	scoreboard_lines        []string
	scoreboard_shown        bool
}

fn (mut s RecordingSender) send_message(message string) ! {
	s.messages << message
}

fn (mut s RecordingSender) send_translation(key string, parameters []string) ! {
	s.messages << '${key} ${parameters}'
}

fn (mut s RecordingSender) set_gamemode(mode player.Gamemode) {
	s.gamemode = mode
}

fn (s &RecordingSender) has_permission(name string) bool {
	return s.perm.has_permission(name)
}

fn (s &RecordingSender) name() string {
	return s.sender_name
}

fn (s &RecordingSender) is_player() bool {
	return s.is_player_val
}

fn (mut s RecordingSender) find_player(name string) ?cmd.Sender {
	return s.peers[name.to_lower()] or { none }
}

fn (mut s RecordingSender) set_operator(value bool) {
	s.perm.set_op(value)
}

fn (mut s RecordingSender) disconnect(message string) {
	s.disconnected = true
	s.disconnect_msg = message
}

fn (mut s RecordingSender) kill() {
	s.killed = true
}

fn (mut s RecordingSender) position() types.Vector3 {
	return types.Vector3{s.pos_x, s.pos_y, s.pos_z}
}

fn (mut s RecordingSender) place_water(x int, y int, z int) {}

fn (mut s RecordingSender) teleport(x f32, y f32, z f32) {
	s.pos_x = x
	s.pos_y = y
	s.pos_z = z
}

fn (mut s RecordingSender) clear_inventory() {
	s.cleared = true
}

fn (mut s RecordingSender) give_experience(points int) {
	s.given_experience += points
}

fn (mut s RecordingSender) give_experience_levels(levels int) {
	s.given_experience_levels += levels
}

fn (s RecordingSender) experience_level() int {
	return s.given_experience_levels
}

fn (mut s RecordingSender) give_item(id string, count int) bool {
	if !s.given_ok {
		return false
	}
	s.given_id = id
	s.given_count = count
	return true
}

fn (s &RecordingSender) whitelist_enabled() bool {
	return s.whitelist_on
}

fn (s &RecordingSender) whitelist_names() []string {
	return s.whitelisted
}

fn (mut s RecordingSender) whitelist_add(name string) {
	s.whitelisted << name.to_lower()
}

fn (mut s RecordingSender) whitelist_remove(name string) {
	needle := name.to_lower()
	s.whitelisted = s.whitelisted.filter(it != needle)
}

fn (mut s RecordingSender) whitelist_set_enabled(value bool) {
	s.whitelist_on = value
}

fn (mut s RecordingSender) set_difficulty(value int) {
	s.difficulty_value = value
}

fn (mut s RecordingSender) broadcast_message(text string) {
	s.broadcasts << text
}

fn (mut s RecordingSender) show_title(kind int, text string) {
	s.shown_title = text
}

fn (mut s RecordingSender) broadcast_title(kind int, text string) {
	s.broadcast_titles << text
}

fn (mut s RecordingSender) send_scoreboard(board &scoreboard.Scoreboard) {
	s.scoreboard_title = board.name()
	s.scoreboard_lines = board.lines()
	s.scoreboard_shown = true
}

fn (mut s RecordingSender) send_title(t title.Title) {
	s.shown_title = t.text()
}

fn (mut s RecordingSender) send_bossbar(bar bossbar.BossBar) {
	s.bossbar_text = bar.text()
}

fn (mut s RecordingSender) remove_bossbar() {
	s.bossbar_text = ''
}

fn (mut s RecordingSender) remove_scoreboard() {
	s.scoreboard_shown = false
}

fn (mut s RecordingSender) send_form(f form.Form) ! {
	s.sent_form = f
}

fn (mut s RecordingSender) world_names() []string {
	return s.worlds
}

fn (mut s RecordingSender) world_info(name string) ?cmd.WorldSummary {
	if name !in s.worlds {
		return none
	}
	return cmd.WorldSummary{
		name: name
	}
}

fn (mut s RecordingSender) world_metrics(name string) ?cmd.WorldMetricsSummary {
	if name !in s.worlds {
		return none
	}
	return cmd.WorldMetricsSummary{
		name: name
	}
}

fn (mut s RecordingSender) world_create(name string, dimension string, generator string) ! {
	s.worlds << name
	s.created_dim = dimension
	s.created_gen = generator
}

fn (mut s RecordingSender) world_load(name string) ! {
	if name in s.worlds {
		return error('world "${name}" is already loaded')
	}
	if name !in s.unloaded_worlds {
		return error('world "${name}" does not exist on disk')
	}
	s.worlds << name
}

fn (mut s RecordingSender) world_delete(name string) ! {
	s.worlds = s.worlds.filter(it != name)
}

fn (mut s RecordingSender) world_teleport(name string) ! {
	s.tp_world = name
}

fn test_version_command() {
	r := full_registry()
	mut sender := RecordingSender{}
	r.dispatch('/version', mut sender, base_ctx())!
	assert sender.messages.len == 1
	assert sender.messages[0].contains('Vedrock')
	assert sender.messages[0].contains(proto.selected_minecraft_version)
	assert sender.messages[0].contains(proto.selected_protocol.str())
}

fn test_version_alias() {
	r := full_registry()
	mut sender := RecordingSender{}
	r.dispatch('/ver', mut sender, base_ctx())!
	assert sender.messages[0].contains('Vedrock')
}

fn test_status_command() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('status', mut sender, base_ctx())!
	assert sender.messages[0].contains('3')
	assert sender.messages[0].contains('20')
	assert sender.messages[0].contains('Vedrock Server')
}

fn test_status_command_denied_without_op() {
	r := full_registry()
	mut sender := RecordingSender{}
	r.dispatch('status', mut sender, base_ctx())!
	assert sender.messages[0].contains('permission')
}

fn test_unknown_command() {
	r := full_registry()
	mut sender := RecordingSender{}
	r.dispatch('/nope', mut sender, base_ctx())!
	assert sender.messages[0].contains('Unknown command')
}

fn test_gamemode_command() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/gamemode creative', mut sender, base_ctx())!
	assert (sender.gamemode or { panic('gamemode was never set') }) == .creative
	assert sender.messages[0].contains('commands.gamemode.success.self')
}

fn test_gamemode_command_usage_is_not_a_client_translation_key() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/gamemode', mut sender, base_ctx())!
	assert sender.gamemode == none
	assert sender.messages[0].contains('Usage')
	assert !sender.messages[0].contains('commands.gamemode.usage')
}

fn test_gamemode_command_denied_without_op() {
	r := full_registry()
	mut sender := RecordingSender{}
	r.dispatch('/gamemode creative', mut sender, base_ctx())!
	assert sender.gamemode == none
	assert sender.messages[0].contains('permission')
}

struct FakeCommand {}

fn (c FakeCommand) name() string {
	return 'fake'
}

fn (c FakeCommand) description() string {
	return 'a fake command for tests'
}

fn (c FakeCommand) aliases() []string {
	return ['fk']
}

fn (c FakeCommand) permission() string {
	return ''
}

fn (c FakeCommand) arguments() []cmd.Argument {
	return []
}

fn (c FakeCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	sender.send_message('fake ran')!
}

fn test_unregister_removes_command_and_aliases() {
	mut r := cmd.new_registry()
	r.register(FakeCommand{})
	mut sender := RecordingSender{}
	r.dispatch('/fake', mut sender, base_ctx())!
	assert sender.messages[0] == 'fake ran'

	r.unregister('fake')

	if _ := r.resolve('fake') {
		assert false
	}
	if _ := r.resolve('fk') {
		assert false
	}
}

fn test_unregister_unknown_command_is_a_noop() {
	mut r := cmd.new_registry()
	r.unregister('ghost')
}

fn test_resolve_missing() {
	r := full_registry()
	if _ := r.resolve('ghost') {
		assert false
	}
}

fn test_command_request_roundtrip() {
	pkt := proto.CommandRequestPacket{
		command:        '/version'
		command_origin: proto.CommandOriginData{
			command_type: proto.CommandOriginType.player
			request_id:   'req-1'
		}
		version:        '1'
	}
	encoded := protocol.encode_packet_to_bytes(&pkt)
	mut pool := proto.new_packet_pool()
	mut reader := serializer.new_reader(encoded)
	decoded := pool.decode(mut reader)!
	assert decoded.name() == 'CommandRequestPacket'
	mut request := proto.CommandRequestPacket{}
	decode_into(&pkt, mut request)!
	assert request.command == '/version'
	assert request.command_origin.command_type == proto.CommandOriginType.player
	assert request.command_origin.request_id == 'req-1'
}

fn test_available_commands_roundtrip() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	pkt := r.available_commands(sender)
	assert pkt.commands.len == 15
	encoded := protocol.encode_packet_to_bytes(pkt)
	mut pool := proto.new_packet_pool()
	mut reader := serializer.new_reader(encoded)
	decoded := pool.decode(mut reader)!
	assert decoded.name() == 'AvailableCommandsPacket'
	mut available := proto.AvailableCommandsPacket{}
	decode_into(pkt, mut available)!
	assert available.commands.len == 15
	assert available.commands[0].alias_enum == -1
	assert available.commands[0].overloads.len == 1
}

fn test_world_list_reports_loaded_worlds() {
	r := full_registry()
	mut sender := RecordingSender{
		worlds: ['world', 'nether']
	}
	sender.perm.set_op(true)
	r.dispatch('/world list', mut sender, base_ctx())!
	assert sender.messages[0].contains('world')
	assert sender.messages[0].contains('nether')
}

fn test_world_metrics_reports_for_loaded_world() {
	r := full_registry()
	mut sender := RecordingSender{
		worlds: ['world']
	}
	sender.perm.set_op(true)
	r.dispatch('/world metrics world', mut sender, base_ctx())!
	assert sender.messages[0].contains('world')
}

fn test_world_metrics_missing_world_reports_not_found() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/world metrics ghost_world', mut sender, base_ctx())!
	assert sender.messages.last().contains('ghost_world')
}

fn test_world_create_and_delete() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/world create arena', mut sender, base_ctx())!
	assert 'arena' in sender.worlds
	assert sender.created_dim == 'overworld'
	assert sender.created_gen == ''
	r.dispatch('/world delete arena', mut sender, base_ctx())!
	assert 'arena' !in sender.worlds
}

fn test_world_create_with_dimension_and_generator() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/world create nether_test nether flat', mut sender, base_ctx())!
	assert 'nether_test' in sender.worlds
	assert sender.created_dim == 'nether'
	assert sender.created_gen == 'flat'
}

fn test_world_load_brings_back_an_on_disk_world() {
	r := full_registry()
	mut sender := RecordingSender{
		unloaded_worlds: ['from_before_restart']
	}
	sender.perm.set_op(true)
	r.dispatch('/world load from_before_restart', mut sender, base_ctx())!
	assert 'from_before_restart' in sender.worlds
	assert sender.messages.last().contains('from_before_restart')
}

fn test_world_load_missing_world_reports_failure() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/world load ghost_world', mut sender, base_ctx())!
	assert 'ghost_world' !in sender.worlds
	assert sender.messages.last().contains('ghost_world')
}

fn test_world_denied_without_op() {
	r := full_registry()
	mut sender := RecordingSender{}
	r.dispatch('/world list', mut sender, base_ctx())!
	assert sender.messages[0].contains('permission')
}

fn test_world_missing_name_shows_usage() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/world create', mut sender, base_ctx())!
	assert sender.messages[0].contains('Usage')
}

fn test_available_commands_filtered() {
	r := full_registry()
	sender := RecordingSender{}
	pkt := r.available_commands(sender)
	assert pkt.commands.len == 1
	assert pkt.commands[0].name == 'version'
}

fn test_available_commands_deduplicates_shared_enum_values() {
	mut r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	pkt := r.available_commands(sender)
	mut seen := map[string]bool{}
	for v in pkt.enum_values {
		assert !seen[v], 'enum_values contains a duplicate: ${v}'
		seen[v] = true
	}
	mut gamemode_enum := proto.EnumDataEntry{}
	mut difficulty_enum := proto.EnumDataEntry{}
	for e in pkt.enum_data {
		if e.name == 'gamemode_mode' {
			gamemode_enum = e
		}
		if e.name == 'difficulty_difficulty' {
			difficulty_enum = e
		}
	}
	assert gamemode_enum.name == 'gamemode_mode'
	assert difficulty_enum.name == 'difficulty_difficulty'
	mut gamemode_values := []string{}
	for idx in gamemode_enum.values {
		gamemode_values << pkt.enum_values[idx]
	}
	mut difficulty_values := []string{}
	for idx in difficulty_enum.values {
		difficulty_values << pkt.enum_values[idx]
	}
	assert gamemode_values == ['survival', 's', '0', 'creative', 'c', '1', 'adventure', 'a', '2',
		'spectator']
	assert difficulty_values == ['peaceful', 'p', '0', 'easy', 'e', '1', 'normal', 'n', '2', 'hard',
		'h', '3']
}

// decode_into reads a packet's payload back into a typed value. The pool builds
// the type the version module declares, which an alias of it does not stand in
// for, so the fields are read back directly instead of through a type check.
fn decode_into[T](p protocol.Packet, mut out T) ! {
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(p))
	protocol.read_packet_header(mut r)!
	out.decode_payload(mut r)!
}

fn test_xp_command_gives_points_to_the_sender() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/xp 30', mut sender, base_ctx())!
	assert sender.given_experience == 30
	assert sender.given_experience_levels == 0
}

fn test_xp_command_reads_the_level_suffix() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/xp 5L', mut sender, base_ctx())!
	assert sender.given_experience_levels == 5
	assert sender.given_experience == 0
}

fn test_xp_command_targets_another_player() {
	r := full_registry()
	mut target := RecordingSender{
		sender_name: 'Alex'
	}
	mut sender := RecordingSender{
		peers: {
			'alex': cmd.Sender(&target)
		}
	}
	sender.perm.set_op(true)
	r.dispatch('/xp 12 Alex', mut sender, base_ctx())!
	assert target.given_experience == 12
	assert sender.given_experience == 0
}

fn test_xp_command_rejects_a_malformed_amount() {
	r := full_registry()
	mut sender := RecordingSender{}
	sender.perm.set_op(true)
	r.dispatch('/xp lots', mut sender, base_ctx())!
	assert sender.given_experience == 0
	assert sender.messages[0].contains('Usage')
}

fn test_xp_command_denied_without_op() {
	r := full_registry()
	mut sender := RecordingSender{}
	r.dispatch('/xp 10', mut sender, base_ctx())!
	assert sender.given_experience == 0
	assert sender.messages[0].contains('permission')
}
