module form

import json2

pub struct SimpleForm {
mut:
	title    string
	content  string
	buttons  []Button
	on_click []fn () !
	on_close ?fn ()
}

pub fn new_simple_form(title string) SimpleForm {
	return SimpleForm{
		title: title
	}
}

pub fn (mut f SimpleForm) body(content string) SimpleForm {
	f.content = content
	return f
}

pub fn (mut f SimpleForm) button(text string, on_click fn () !) SimpleForm {
	f.buttons << button(text)
	f.on_click << on_click
	return f
}

pub fn (mut f SimpleForm) image_button(text string, image string, on_click fn () !) SimpleForm {
	f.buttons << image_button(text, image)
	f.on_click << on_click
	return f
}

// closed sets a callback invoked if the player closes the form without tapping a button.
pub fn (mut f SimpleForm) closed(on_close fn ()) SimpleForm {
	f.on_close = on_close
	return f
}

pub fn (f &SimpleForm) request_body() string {
	mut parts := []string{cap: f.buttons.len}
	for b in f.buttons {
		parts << json2.encode(b, escape_unicode: true)
	}
	return '{"type":"form","title":${json2.encode(f.title, escape_unicode: true)},"content":${json2.encode(f.content, escape_unicode: true)},"buttons":[${parts.join(',')}]}'
}

pub fn (f &SimpleForm) has_network_image() bool {
	for b in f.buttons {
		if b.has_network_image() {
			return true
		}
	}
	return false
}

pub fn (f &SimpleForm) submit(raw ?string) ! {
	data := raw or {
		if callback := f.on_close {
			callback()
		}
		return
	}

	index := data.int()
	if index < 0 || index >= f.on_click.len {
		return error('form: button index ${index} out of range (${f.on_click.len} buttons)')
	}
	f.on_click[index]()!
}
