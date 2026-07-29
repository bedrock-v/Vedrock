module session

import time
import protocol.version.v662.packets as packets_662
import server.form

const form_image_resync_attempts = 5
const form_image_resync_interval_ms = 500

// send_form queues the form for the target player, since it may be opened
// from a command running on another session's thread.
fn (mut s NetworkSession) send_form(f form.Form) ! {
	s.forms_mutex.lock()
	s.next_form_id++
	id := s.next_form_id
	s.pending_forms[id] = f
	s.forms_mutex.unlock()
	s.deliver(&packets_662.ModalFormRequestPacket{
		form_id:      u32(id)
		form_ui_json: f.request_body()
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

fn (mut s NetworkSession) handle_modal_form_response(p packets_662.ModalFormResponsePacket) ! {
	s.forms_mutex.lock()
	form_id := int(p.form_id)
	f := s.pending_forms[form_id] or {
		s.forms_mutex.unlock()
		return
	}
	s.pending_forms.delete(form_id)
	s.forms_mutex.unlock()
	response := p.json_response or { return }
	f.submit(response)!
}
