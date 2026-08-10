module session

import encoding.base64
import os
import time
import protocol.serializer
import server.internal.network
import protocol.version.v662.packets as packets_662
import protocol.version.v2168.packets as packets_2168
import protocol.version.v1001.packets as packets_1001
import server.conf
import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.permission
import server.player

fn login_test_token(name string, xuid string, uuid string) string {
	header := base64.url_encode('{"alg":"none"}'.bytes()).trim_right('=')
	payload :=
		base64.url_encode('{"xid":"${xuid}","xname":"${name}","identity":"${uuid}","cpk":""}'.bytes()).trim_right('=')
	return '${header}.${payload}.unsigned'
}

fn login_test_packet(name string, uuid string) packets_662.LoginPacket {
	auth_info_json := '{"AuthenticationType":2,"Token":"${login_test_token(name, '', uuid)}"}'
	mut w := serializer.new_writer()
	w.le_u32(u32(auth_info_json.len))
	w.write_raw(auth_info_json.bytes())
	return packets_662.LoginPacket{
		client_network_version: network.selected_protocol
		connection_request:     w.bytes()
	}
}

fn login_test_session(mut hub Hub, name string) (&NetworkSession, &FakeTransport) {
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:    player.new_player()
		transport: transport
		hub:       hub
		cfg:       conf.Config{
			xbox_auth:      false
			resource_packs: false
		}
		log:       logger.new(.info)
	}
	s.player.identity = auth.Identity{
		display_name: name
	}
	return s, transport
}

fn sent_packet[T](transport &FakeTransport) bool {
	for p in transport.sent {
		if p is T {
			return true
		}
	}
	return false
}

fn wait_for_sent[T](transport &FakeTransport, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for !sent_packet[T](transport) {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return sent_packet[T](transport)
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return sent_packet[T](transport)
		}
	}
	return true
}

fn test_duplicate_login_rejected_while_first_session_is_pending_spawn() {
	mut hub := new_hub(gamedata.GameData{})
	mut first, first_transport := login_test_session(mut hub, 'Alex')
	mut second, second_transport := login_test_session(mut hub, 'Alex')
	packet := login_test_packet('Alex', '00000000-0000-0000-0000-000000000001')

	first.handle_login(packet)!
	second.handle_login(packet)!

	assert sent_packet[packets_2168.ResourcePacksInfoPacket](first_transport)
	assert wait_for_sent[packets_1001.DisconnectPacket](second_transport, 5000)
	assert second.state == .closed
}

// login_test_packet_with_xuid builds a LoginPacket claiming the given xuid.
fn login_test_packet_with_xuid(name string, xuid string, uuid string) packets_662.LoginPacket {
	auth_info_json := '{"AuthenticationType":2,"Token":"${login_test_token(name, xuid, uuid)}"}'
	mut w := serializer.new_writer()
	w.le_u32(u32(auth_info_json.len))
	w.write_raw(auth_info_json.bytes())
	return packets_662.LoginPacket{
		client_network_version: network.selected_protocol
		connection_request:     w.bytes()
	}
}

fn test_player_key_ignores_unauthenticated_xuid_claim() {
	mut hub := new_hub(gamedata.GameData{})
	mut s, _ := login_test_session(mut hub, 'Steve')
	packet := login_test_packet_with_xuid('Steve', '2535400000000001',
		'00000000-0000-0000-0000-000000000099')

	s.handle_login(packet)!

	assert !s.player.identity.xbox_authenticated
	assert s.player.identity.xuid == '2535400000000001'
	assert s.player_key() == 'Steve'
}

fn test_grants_apply_ignores_unauthenticated_xuid_claim() {
	path := os.join_path(os.temp_dir(), 'vedrock_player_grants_test_${os.getpid()}.yml')
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, 'xuid:2535400000000001: ${permission.command_status}') or { panic(err) }

	mut hub := new_hub(gamedata.GameData{})
	hub.player_grants = permission.load_player_grants(path)!
	mut s, _ := login_test_session(mut hub, 'Steve')
	packet := login_test_packet_with_xuid('Steve', '2535400000000001',
		'00000000-0000-0000-0000-000000000099')

	s.handle_login(packet)!

	assert !s.player.identity.xbox_authenticated
	assert !s.player.perm.has_permission(permission.command_status)
}

fn test_max_players_counts_pending_logins_before_reserving_name() {
	mut hub := new_hub(gamedata.GameData{})
	mut first, first_transport := login_test_session(mut hub, 'Alex')
	mut second, second_transport := login_test_session(mut hub, 'Steve')
	first.cfg.max_players = 1
	second.cfg.max_players = 1
	first_packet := login_test_packet('Alex', '00000000-0000-0000-0000-000000000001')
	second_packet := login_test_packet('Steve', '00000000-0000-0000-0000-000000000002')

	first.handle_login(first_packet)!
	second.handle_login(second_packet)!

	assert sent_packet[packets_2168.ResourcePacksInfoPacket](first_transport)
	assert wait_for_sent[packets_1001.DisconnectPacket](second_transport, 5000)
	assert second.state == .closed
}
