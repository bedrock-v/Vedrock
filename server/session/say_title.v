module session

import protocol
import protocol.enums

pub fn (mut s NetworkSession) broadcast_message(text string) {
	s.hub.broadcast(&protocol.TextPacket{
		@type:       int(enums.TextType.chat)
		source_name: 'Server'
		message:     text
	})
}

pub fn (mut s NetworkSession) show_title(kind int, text string) {
	s.transport.send(&protocol.SetTitlePacket{
		type: kind
		text: text
	}) or {}
}

pub fn (mut s NetworkSession) broadcast_title(kind int, text string) {
	s.hub.broadcast(&protocol.SetTitlePacket{
		type: kind
		text: text
	})
}

pub fn (mut c ConsoleSender) broadcast_message(text string) {
	c.hub.broadcast(&protocol.TextPacket{
		@type:       int(enums.TextType.chat)
		source_name: 'Server'
		message:     text
	})
}

pub fn (mut c ConsoleSender) show_title(kind int, text string) {
	// The console has no client to render a title on.
}

pub fn (mut c ConsoleSender) broadcast_title(kind int, text string) {
	c.hub.broadcast(&protocol.SetTitlePacket{
		type: kind
		text: text
	})
}
