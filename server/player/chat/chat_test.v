module chat

struct Recorder {
	id u64
mut:
	received []string
}

fn (r &Recorder) subscriber_id() u64 {
	return r.id
}

fn (mut r Recorder) message(text string) {
	r.received << text
}

fn test_write_reaches_every_subscriber() {
	mut c := new()
	mut first := &Recorder{
		id: 1
	}
	mut second := &Recorder{
		id: 2
	}
	c.subscribe(first)
	c.subscribe(second)
	c.write('hello')
	assert first.received == ['hello']
	assert second.received == ['hello']
}

fn test_unsubscribe_stops_delivery() {
	mut c := new()
	mut sub := &Recorder{
		id: 1
	}
	c.subscribe(sub)
	c.unsubscribe(1)
	c.write('hello')
	assert sub.received.len == 0
	assert c.subscriber_count() == 0
}

fn test_subscribing_twice_keeps_one_subscription() {
	mut c := new()
	mut sub := &Recorder{
		id: 1
	}
	c.subscribe(sub)
	c.subscribe(sub)
	c.write('hello')
	assert sub.received == ['hello']
	assert c.subscriber_count() == 1
}

fn test_translation_with_replaces_only_the_parameters() {
	t := translate('chat.type.text', ['Steve'])
	other := t.with(['Alex'])
	assert other.key == 'chat.type.text'
	assert other.parameters == ['Alex']
	assert t.parameters == ['Steve']
}
