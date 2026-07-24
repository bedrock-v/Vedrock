module session

// whitelist_add/remove/set_enabled mutate the server-global whitelist under
// config_mutex, released before logging. config_mutex must never be held
// across anything that can block, the same rule set_difficulty follows.
pub fn (mut h Hub) whitelist_add(name string) {
	h.config_mutex.lock()
	h.whitelist.add(name) or {
		h.config_mutex.unlock()
		eprintln('Failed to persist whitelist add for ${name}: ${err}')
		return
	}
	h.config_mutex.unlock()
}

pub fn (mut h Hub) whitelist_remove(name string) {
	h.config_mutex.lock()
	h.whitelist.remove(name) or {
		h.config_mutex.unlock()
		eprintln('Failed to persist whitelist remove for ${name}: ${err}')
		return
	}
	h.config_mutex.unlock()
}

pub fn (mut h Hub) whitelist_set_enabled(value bool) {
	h.config_mutex.lock()
	h.whitelist.set_enabled(value) or {
		h.config_mutex.unlock()
		eprintln('Failed to persist whitelist enabled=${value}: ${err}')
		return
	}
	h.config_mutex.unlock()
}

// whitelist_allowed/whitelist_enabled_value/whitelist_names_list are locked
// read paths for login and runtime admin checks.
pub fn (mut h Hub) whitelist_allowed(name string) bool {
	h.config_mutex.lock()
	defer {
		h.config_mutex.unlock()
	}
	return h.whitelist.is_allowed(name)
}

pub fn (mut h Hub) whitelist_enabled_value() bool {
	h.config_mutex.lock()
	defer {
		h.config_mutex.unlock()
	}
	return h.whitelist.is_enabled()
}

pub fn (mut h Hub) whitelist_names_list() []string {
	h.config_mutex.lock()
	defer {
		h.config_mutex.unlock()
	}
	return h.whitelist.names_list()
}

pub fn (mut s NetworkSession) whitelist_add(name string) {
	s.hub.whitelist_add(name)
}

pub fn (mut s NetworkSession) whitelist_remove(name string) {
	s.hub.whitelist_remove(name)
}

pub fn (mut s NetworkSession) whitelist_set_enabled(value bool) {
	s.hub.whitelist_set_enabled(value)
}

pub fn (s &NetworkSession) whitelist_enabled() bool {
	mut h := s.hub
	return h.whitelist_enabled_value()
}

pub fn (s &NetworkSession) whitelist_names() []string {
	mut h := s.hub
	return h.whitelist_names_list()
}

pub fn (mut c ConsoleSender) whitelist_add(name string) {
	c.hub.whitelist_add(name)
}

pub fn (mut c ConsoleSender) whitelist_remove(name string) {
	c.hub.whitelist_remove(name)
}

pub fn (mut c ConsoleSender) whitelist_set_enabled(value bool) {
	c.hub.whitelist_set_enabled(value)
}

pub fn (c &ConsoleSender) whitelist_enabled() bool {
	mut h := c.hub
	return h.whitelist_enabled_value()
}

pub fn (c &ConsoleSender) whitelist_names() []string {
	mut h := c.hub
	return h.whitelist_names_list()
}
