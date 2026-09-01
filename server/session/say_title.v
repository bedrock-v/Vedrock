module session

import bedrock_v.protocol.current as proto
import server.player.title

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

// send_title shows t on the player's screen. The durations are pushed first so
// the client applies them to the text that follows, and only the parts of the
// title that carry text are sent.
fn (mut s NetworkSession) send_title(t title.Title) {
	s.deliver(&proto.SetTitlePacket{
		title_type:    .times
		fade_in_time:  title.ticks(t.fade_in_duration())
		stay_time:     title.ticks(t.duration())
		fade_out_time: title.ticks(t.fade_out_duration())
	})
	if t.text() != '' || t.subtitle() != '' {
		s.show_title(int(proto.SetTitleType.title), t.text())
	}
	if t.subtitle() != '' {
		s.show_title(int(proto.SetTitleType.subtitle), t.subtitle())
	}
	if t.action_text() != '' {
		s.show_title(int(proto.SetTitleType.actionbar), t.action_text())
	}
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

fn (mut c ConsoleSender) send_title(_ title.Title) {}

fn (mut c ConsoleSender) broadcast_title(kind int, text string) {
	c.hub.broadcast(&proto.SetTitlePacket{
		title_type: unsafe { proto.SetTitleType(kind) }
		title_text: text
	})
}
