module form

import json2

pub type Element = Divider | Dropdown | Header | Input | Label | Slider | StepSlider | Toggle

pub struct Divider {
pub:
	typ  string = 'divider' @[json: 'type']
	text string
}

pub fn divider() Element {
	return Divider{}
}

pub struct Header {
pub:
	typ  string = 'header' @[json: 'type']
	text string
}

pub fn header(text string) Element {
	return Header{
		text: text
	}
}

pub struct Label {
pub:
	typ  string = 'label' @[json: 'type']
	text string
}

pub fn label(text string) Element {
	return Label{
		text: text
	}
}

pub struct Input {
pub:
	typ         string = 'input' @[json: 'type']
	text        string
	default     string
	placeholder string
}

pub fn input(text string, default_value string, placeholder string) Element {
	return Input{
		text:        text
		default:     default_value
		placeholder: placeholder
	}
}

pub struct Toggle {
pub:
	typ     string = 'toggle' @[json: 'type']
	text    string
	default bool
}

pub fn toggle(text string, default_value bool) Element {
	return Toggle{
		text:    text
		default: default_value
	}
}

pub struct Slider {
pub:
	typ     string = 'slider' @[json: 'type']
	text    string
	min     f64
	max     f64
	step    f64
	default f64
}

pub fn slider(text string, min f64, max f64, step f64, default_value f64) Element {
	return Slider{
		text:    text
		min:     min
		max:     max
		step:    step
		default: default_value
	}
}

pub struct Dropdown {
pub:
	typ           string = 'dropdown' @[json: 'type']
	text          string
	options       []string
	default_index int @[json: 'default']
}

pub fn dropdown(text string, options []string, default_index int) Element {
	return Dropdown{
		text:          text
		options:       options
		default_index: default_index
	}
}

pub struct StepSlider {
pub:
	typ           string = 'step_slider' @[json: 'type']
	text          string
	options       []string @[json: 'steps']
	default_index int      @[json: 'default']
}

pub fn step_slider(text string, options []string, default_index int) Element {
	return StepSlider{
		text:          text
		options:       options
		default_index: default_index
	}
}

fn (e Element) encode() string {
	match e {
		Divider { return json2.encode(e, escape_unicode: true) }
		Header { return json2.encode(e, escape_unicode: true) }
		Label { return json2.encode(e, escape_unicode: true) }
		Input { return json2.encode(e, escape_unicode: true) }
		Toggle { return json2.encode(e, escape_unicode: true) }
		Slider { return json2.encode(e, escape_unicode: true) }
		Dropdown { return json2.encode(e, escape_unicode: true) }
		StepSlider { return json2.encode(e, escape_unicode: true) }
	}
}
