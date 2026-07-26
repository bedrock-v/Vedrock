module session

import protocol
import protocol.enums

fn (mut s NetworkSession) broadcast_message(text string) {
	s.hub.broadcast(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           '%chat.type.announcement'
		parameters:        [s.player.identity.display_name, text]
	})
}

// show_title displays a title packet on the selected player's screen.
// Using deliver keeps command triggered titles off the caller's socket path.
fn (mut s NetworkSession) show_title(kind int, text string) {
	s.deliver(&protocol.SetTitlePacket{
		type: kind
		text: text
	})
}

fn (mut s NetworkSession) broadcast_title(kind int, text string) {
	s.hub.broadcast(&protocol.SetTitlePacket{
		type: kind
		text: text
	})
}

fn (mut c ConsoleSender) broadcast_message(text string) {
	c.hub.broadcast(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           '%chat.type.announcement'
		parameters:        ['Server', text]
	})
}

fn (mut c ConsoleSender) show_title(kind int, text string) {
	// The console has no client to render a title on.
}

fn (mut c ConsoleSender) broadcast_title(kind int, text string) {
	c.hub.broadcast(&protocol.SetTitlePacket{
		type: kind
		text: text
	})
}
