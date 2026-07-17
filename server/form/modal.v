module form

import json2

pub struct ModalForm {
mut:
	title      string
	content    string
	button1    string  = 'gui.yes'
	button2    string  = 'gui.no'
	on_button1 fn () ! = unsafe { nil }
	on_button2 fn () ! = unsafe { nil }
	on_close   ?fn ()
}

pub fn new_modal_form(title string, on_button1 fn () !, on_button2 fn () !) ModalForm {
	return ModalForm{
		title:      title
		on_button1: on_button1
		on_button2: on_button2
	}
}

pub fn (mut f ModalForm) body(content string) ModalForm {
	f.content = content
	return f
}

pub fn (mut f ModalForm) buttons(button1 string, button2 string) ModalForm {
	f.button1 = button1
	f.button2 = button2
	return f
}

pub fn (mut f ModalForm) closed(on_close fn ()) ModalForm {
	f.on_close = on_close
	return f
}

pub fn (f &ModalForm) request_body() string {
	return '{"type":"modal","title":${json2.encode(f.title, escape_unicode: true)},"content":${json2.encode(f.content, escape_unicode: true)},"button1":${json2.encode(f.button1, escape_unicode: true)},"button2":${json2.encode(f.button2, escape_unicode: true)}}'
}

// has_network_image is always false because modal form buttons don't carry images.
pub fn (f &ModalForm) has_network_image() bool {
	return false
}

pub fn (f &ModalForm) submit(raw ?string) ! {
	data := raw or {
		if callback := f.on_close {
			callback()
		}
		return
	}

	if data == 'true' {
		f.on_button1()!
		return
	}
	f.on_button2()!
}
