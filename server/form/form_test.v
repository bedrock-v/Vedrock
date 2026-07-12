module form

@[heap]
struct Recorder {
mut:
	clicked  int = -1
	closed   bool
	yes      bool
	no       bool
	response Response
}

fn test_simple_request_body() {
	mut f := new_simple_form('Menu')
	f = f.body('pick one')
	f = f.button('First', fn () ! {})
	f = f.image_button('Second', 'textures/blocks/grass_carried', fn () ! {})

	body := f.request_body()
	assert body.contains('"type":"form"')
	assert body.contains('"title":"Menu"')
	assert body.contains('"content":"pick one"')
	assert body.contains('"text":"First"')
	assert body.contains('"image":{"type":"path","data":"textures/blocks/grass_carried"}')
}

fn test_simple_submit_by_index() {
	mut rec := &Recorder{}
	mut f := new_simple_form('Menu')
	f = f.button('A', fn [mut rec] () ! {
		rec.clicked = 0
	})
	f = f.button('B', fn [mut rec] () ! {
		rec.clicked = 1
	})

	f.submit('1')!
	assert rec.clicked == 1
}

fn test_simple_submit_out_of_range() {
	mut f := new_simple_form('Menu')
	f = f.button('A', fn () ! {})

	f.submit('5') or {
		assert err.msg().contains('out of range')
		return
	}
	assert false
}

fn test_simple_close_callback() {
	mut rec := &Recorder{}
	mut f := new_simple_form('Menu')
	f = f.button('A', fn () ! {})
	f = f.closed(fn [mut rec] () {
		rec.closed = true
	})

	f.submit(none)!
	assert rec.closed
}

fn test_modal_request_and_dispatch() {
	mut rec := &Recorder{}
	mut f := new_modal_form('Confirm?', fn [mut rec] () ! {
		rec.yes = true
	}, fn [mut rec] () ! {
		rec.no = true
	})
	f = f.body('are you sure')

	body := f.request_body()
	assert body.contains('"type":"modal"')
	assert body.contains('"button1":"gui.yes"')
	assert body.contains('"button2":"gui.no"')

	f.submit('false')!
	assert rec.no
	assert !rec.yes
}

fn test_custom_round_trip() {
	mut rec := &Recorder{}
	mut f := new_custom_form('Settings', fn [mut rec] (r Response) ! {
		rec.response = r
	})
	f = f.element(label('welcome'))
	f = f.element(input('Name', '', 'enter name'))
	f = f.element(toggle('PVP', false))

	body := f.request_body()
	assert body.contains('"type":"custom_form"')
	assert body.contains('"type":"label"')
	assert body.contains('"type":"input"')
	assert body.contains('"type":"toggle"')

	f.submit('[null, "Alex", true]')!
	assert rec.response.len() == 3
	assert rec.response.string_value(1) == 'Alex'
	assert rec.response.bool_value(2) == true
}

fn test_custom_response_length_mismatch() {
	mut f := new_custom_form('Settings', fn (r Response) ! {})
	f = f.element(input('Name', '', ''))

	f.submit('["Alex", true]') or {
		assert err.msg().contains('expected 1')
		return
	}
	assert false
}
