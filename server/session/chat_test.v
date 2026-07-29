module session

import protocol.version.v924.enums as enums_924
import protocol.version.v924.packets as packets_924
import server.event
import server.internal.gamedata
import server.player
import server.internal.auth
import server.internal.logger

struct RecordingChatHandler {
	event.NopHandler
mut:
	calls int
}

fn (mut h RecordingChatHandler) on_player_chat(mut ctx event.Context[event.ChatData]) {
	h.calls++
}

fn test_handle_text_dispatches_to_per_session_handler() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		log:        logger.new(.info)
	}
	hub.add(s)

	mut per_session := &RecordingChatHandler{}
	s.set_handler(per_session)

	s.handle_text(packets_924.TextPacket{
		message_type: enums_924.TextChat{
			player_name: 'Alex'
			message:     'hello'
		}
	})!

	assert per_session.calls == 1
}
