module session

import server.event
import server.internal.gamedata
import server.player
import server.internal.auth
import server.internal.logger
import protocol.current as proto

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

	s.handle_text(proto.TextPacket{
		message_type: proto.TextChat{
			player_name: 'Alex'
			message:     'hello'
		}
	})!

	assert per_session.calls == 1
}

fn test_sanitize_chat_message_strips_formatting_and_control_characters() {
	assert sanitize_chat_message('§chello') == 'chello'
	assert sanitize_chat_message('hello\nworld') == 'helloworld'
	assert sanitize_chat_message('  spaced  ') == 'spaced'
}

fn test_handle_text_rejects_an_oversized_message() {
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

	s.handle_text(proto.TextPacket{
		message_type: proto.TextChat{
			player_name: 'Alex'
			message:     'a'.repeat(max_chat_message_bytes + 1)
		}
	}) or { return }
	assert false, 'expected an oversized chat message to be rejected'
}
