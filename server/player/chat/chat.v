module chat

import sync

// Subscriber is anything that can receive chat messages: a player session, the
// console, or a log sink. Subscribers are compared by id so one may be removed
// again without holding on to the value itself.
pub interface Subscriber {
	// subscriber_id returns a value that is unique for as long as the
	// subscriber is subscribed.
	subscriber_id() u64
mut:
	// message delivers a line of chat to the subscriber.
	message(text string)
}

// Chat is a channel messages are written to and every subscriber of which
// receives them. Servers use the global chat for public messages, but separate
// channels may be built for teams, staff or worlds.
@[heap]
pub struct Chat {
mut:
	mutex       &sync.Mutex = sync.new_mutex()
	subscribers map[u64]Subscriber
}

const global_chat = &Chat{
	subscribers: map[u64]Subscriber{}
}

// global returns the chat every player is subscribed to while they are online.
pub fn global() &Chat {
	return global_chat
}

// new returns a Chat with no subscribers.
pub fn new() &Chat {
	return &Chat{
		subscribers: map[u64]Subscriber{}
	}
}

// subscribe adds sub to the Chat, replacing an earlier subscriber with the
// same id.
pub fn (mut c Chat) subscribe(sub Subscriber) {
	c.mutex.lock()
	c.subscribers[sub.subscriber_id()] = sub
	c.mutex.unlock()
}

// unsubscribe removes the subscriber with the id passed, if it is subscribed.
pub fn (mut c Chat) unsubscribe(id u64) {
	c.mutex.lock()
	c.subscribers.delete(id)
	c.mutex.unlock()
}

// subscriber_count returns how many subscribers the Chat has.
pub fn (c &Chat) subscriber_count() int {
	mut m := c.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return c.subscribers.len
}

// write sends text to every subscriber. Subscribers are collected under the
// lock and written to outside of it, so a slow subscriber cannot block another
// thread from subscribing.
pub fn (mut c Chat) write(text string) {
	for mut sub in c.snapshot() {
		sub.message(text)
	}
}

fn (c &Chat) snapshot() []Subscriber {
	mut m := c.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := []Subscriber{cap: c.subscribers.len}
	for _, sub in c.subscribers {
		out << sub
	}
	return out
}
