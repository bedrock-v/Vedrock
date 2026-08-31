module session

import server.form
import bedrock_v.protocol.current as proto

// send_form queues the form for the target player, since it may be opened
// from a command running on another session's thread.
fn (mut s NetworkSession) send_form(f form.Form) ! {
	s.forms_mutex.lock()
	s.next_form_id++
	id := s.next_form_id
	s.pending_forms[id] = f
	s.forms_mutex.unlock()
	s.deliver(&proto.ModalFormRequestPacket{
		form_id:      u32(id)
		form_ui_json: f.request_body()
	})
}

fn (mut s NetworkSession) handle_modal_form_response(p proto.ModalFormResponsePacket) ! {
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
