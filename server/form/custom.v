module form

import json2

pub struct CustomForm {
mut:
	title     string
	elements  []Element
	on_submit fn (Response) ! = unsafe { nil }
	on_close  ?fn ()
}

pub fn new_custom_form(title string, on_submit fn (Response) !) CustomForm {
	return CustomForm{
		title:     title
		on_submit: on_submit
	}
}

pub fn (mut f CustomForm) element(e Element) CustomForm {
	f.elements << e
	return f
}

pub fn (mut f CustomForm) closed(on_close fn ()) CustomForm {
	f.on_close = on_close
	return f
}

pub fn (f &CustomForm) request_body() string {
	mut parts := []string{cap: f.elements.len}
	for e in f.elements {
		parts << e.encode()
	}
	return '{"type":"custom_form","title":${json2.encode(f.title, escape_unicode: true)},"content":[${parts.join(',')}]}'
}

// has_network_image is always false because custom form elements don't carry images.
pub fn (f &CustomForm) has_network_image() bool {
	return false
}

pub fn (f &CustomForm) submit(raw ?string) ! {
	data := raw or {
		if callback := f.on_close {
			callback()
		}
		return
	}

	response := parse_response(data)!
	if response.len() != f.elements.len {
		return error('form: expected ${f.elements.len} response values, got ${response.len()}')
	}
	f.on_submit(response)!
}
