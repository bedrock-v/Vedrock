module session

import protocol
import protocol.version.v662.packets as packets_662
import protocol.version.v685.packets as packets_685
import protocol.version.v712.packets as packets_712
import protocol.version.v776.packets as packets_776
import protocol.version.v800.packets as packets_800
import protocol.version.v818.packets as packets_818
import protocol.version.v898.packets as packets_898
import protocol.version.v924.enums as enums_924
import protocol.version.v924.packets as packets_924
import protocol.version.v944.packets as packets_944
import protocol.version.v975.packets as packets_975
import protocol.version.v1001.packets as packets_1001
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
