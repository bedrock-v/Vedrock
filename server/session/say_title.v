module session

import protocol.version.v712.packets as packets_712
import protocol.version.v924.enums as enums_924
import protocol.version.v924.packets as packets_924

fn (mut s NetworkSession) broadcast_message(text string) {
	s.hub.broadcast(&packets_924.TextPacket{
		localize:     true
		message_type: enums_924.TextTranslate{
			message:        '%chat.type.announcement'
			parameter_list: [s.player.identity.display_name, text]
		}
	})
}

// show_title displays a title packet on the selected player's screen.
// Using deliver keeps command triggered titles off the caller's socket path.
fn (mut s NetworkSession) show_title(kind int, text string) {
	s.deliver(&packets_712.SetTitlePacket{
		title_type: unsafe { packets_712.SetTitleType(kind) }
		title_text: text
	})
}

fn (mut s NetworkSession) broadcast_title(kind int, text string) {
	s.hub.broadcast(&packets_712.SetTitlePacket{
		title_type: unsafe { packets_712.SetTitleType(kind) }
		title_text: text
	})
}

fn (mut c ConsoleSender) broadcast_message(text string) {
	c.hub.broadcast(&packets_924.TextPacket{
		localize:     true
		message_type: enums_924.TextTranslate{
			message:        '%chat.type.announcement'
			parameter_list: ['Server', text]
		}
	})
}

fn (mut c ConsoleSender) show_title(_ int, _ string) {
	// The console has no client to render a title on.
}

fn (mut c ConsoleSender) broadcast_title(kind int, text string) {
	c.hub.broadcast(&packets_712.SetTitlePacket{
		title_type: unsafe { packets_712.SetTitleType(kind) }
		title_text: text
	})
}
