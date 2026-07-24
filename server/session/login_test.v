module session

import encoding.base64
import time
import protocol
import server.conf
import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.player

fn login_test_token(name string, xuid string, uuid string) string {
	header := base64.url_encode('{"alg":"none"}'.bytes()).trim_right('=')
	payload :=
		base64.url_encode('{"xid":"${xuid}","xname":"${name}","identity":"${uuid}","cpk":""}'.bytes()).trim_right('=')
	return '${header}.${payload}.unsigned'
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
	token := login_test_token('Alex', '', '00000000-0000-0000-0000-000000000001')
	packet := protocol.LoginPacket{
		auth_info_json: '{"AuthenticationType":2,"Token":"${token}"}'
	}

	first.handle_login(packet)!
	second.handle_login(packet)!

	assert sent_packet[protocol.ResourcePacksInfoPacket](first_transport)
	assert wait_for_sent[protocol.DisconnectPacket](second_transport, 5000)
	assert second.state == .closed
}

fn test_max_players_counts_pending_logins_before_reserving_name() {
	mut hub := new_hub(gamedata.GameData{})
	mut first, first_transport := login_test_session(mut hub, 'Alex')
	mut second, second_transport := login_test_session(mut hub, 'Steve')
	first.cfg.max_players = 1
	second.cfg.max_players = 1
	first_packet := protocol.LoginPacket{
		auth_info_json: '{"AuthenticationType":2,"Token":"${login_test_token('Alex', '',
			'00000000-0000-0000-0000-000000000001')}"}'
	}
	second_packet := protocol.LoginPacket{
		auth_info_json: '{"AuthenticationType":2,"Token":"${login_test_token('Steve', '',
			'00000000-0000-0000-0000-000000000002')}"}'
	}

	first.handle_login(first_packet)!
	second.handle_login(second_packet)!

	assert sent_packet[protocol.ResourcePacksInfoPacket](first_transport)
	assert wait_for_sent[protocol.DisconnectPacket](second_transport, 5000)
	assert second.state == .closed
}
