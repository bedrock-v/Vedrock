module session

import protocol.current as proto

fn (mut s NetworkSession) broadcast_message(text string) {
	s.hub.broadcast(&proto.TextPacket{
		localize:     true
		message_type: proto.TextTranslate{
			message:        '%chat.type.announcement'
			parameter_list: [s.player.identity.display_name, text]
		}
	})
}

// show_title displays a title packet on the selected player's screen.
// Using deliver keeps command triggered titles off the caller's socket path.
fn (mut s NetworkSession) show_title(kind int, text string) {
	s.deliver(&proto.SetTitlePacket{
		title_type: unsafe { proto.SetTitleType(kind) }
		title_text: text
	})
}

fn (mut s NetworkSession) broadcast_title(kind int, text string) {
	s.hub.broadcast(&proto.SetTitlePacket{
		title_type: unsafe { proto.SetTitleType(kind) }
		title_text: text
	})
}

fn (mut c ConsoleSender) broadcast_message(text string) {
	c.hub.broadcast(&proto.TextPacket{
		localize:     true
		message_type: proto.TextTranslate{
			message:        '%chat.type.announcement'
			parameter_list: ['Server', text]
		}
	})
}

fn (mut c ConsoleSender) show_title(_ int, _ string) {
	// The console has no client to render a title on.
}

fn (mut c ConsoleSender) broadcast_title(kind int, text string) {
	c.hub.broadcast(&proto.SetTitlePacket{
		title_type: unsafe { proto.SetTitleType(kind) }
		title_text: text
	})
}
