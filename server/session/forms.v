module session

import time
import protocol
import server.form

const form_image_resync_attempts = 5
const form_image_resync_interval_ms = 500

// send_form queues the form for the target player, since it may be opened
// from a command running on another session's thread.
pub fn (mut s NetworkSession) send_form(f form.Form) ! {
	s.next_form_id++
	id := s.next_form_id
	s.pending_forms[id] = f
	s.deliver(&protocol.ModalFormRequestPacket{
		form_id:   id
		form_data: f.request_body()
	})
	if f.has_network_image() {
		spawn s.resync_attributes_after_form_image()
	}
}

// resync_attributes_after_form_image works around a client bug:
// a form button image loaded over the network ("url") can finish loading
// while the client keeps showing a "loading" spinner over it. Resending an
// attribute update nudges the client into redrawing and clearing it.
// see FormImagesFix(https://github.com/Muqsit/FormImagesFix).
fn (mut s NetworkSession) resync_attributes_after_form_image() {
	for _ in 0 .. form_image_resync_attempts {
		time.sleep(form_image_resync_interval_ms * time.millisecond)
		if s.state == .closed {
			return
		}
		s.send_packet(s.update_attributes()) or { return }
	}
}

fn (mut s NetworkSession) handle_modal_form_response(p protocol.ModalFormResponsePacket) ! {
	f := s.pending_forms[p.form_id] or { return }
	s.pending_forms.delete(p.form_id)
	f.submit(p.form_data)!
}
