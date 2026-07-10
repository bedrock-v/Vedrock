module session

struct WhitelistAddJob {
	name string
}

fn (j WhitelistAddJob) run(mut h Hub) {
	h.whitelist.add(j.name) or {}
}

struct WhitelistRemoveJob {
	name string
}

fn (j WhitelistRemoveJob) run(mut h Hub) {
	h.whitelist.remove(j.name) or {}
}

struct WhitelistSetEnabledJob {
	value bool
}

fn (j WhitelistSetEnabledJob) run(mut h Hub) {
	h.whitelist.set_enabled(j.value) or {}
}

pub fn (mut s NetworkSession) whitelist_add(name string) {
	s.hub.submit(WhitelistAddJob{ name: name })
}

pub fn (mut s NetworkSession) whitelist_remove(name string) {
	s.hub.submit(WhitelistRemoveJob{ name: name })
}

pub fn (mut s NetworkSession) whitelist_set_enabled(value bool) {
	s.hub.submit(WhitelistSetEnabledJob{ value: value })
}

pub fn (s &NetworkSession) whitelist_enabled() bool {
	return s.hub.whitelist.is_enabled()
}

pub fn (s &NetworkSession) whitelist_names() []string {
	return s.hub.whitelist.names_list()
}

pub fn (mut c ConsoleSender) whitelist_add(name string) {
	c.hub.submit(WhitelistAddJob{ name: name })
}

pub fn (mut c ConsoleSender) whitelist_remove(name string) {
	c.hub.submit(WhitelistRemoveJob{ name: name })
}

pub fn (mut c ConsoleSender) whitelist_set_enabled(value bool) {
	c.hub.submit(WhitelistSetEnabledJob{ value: value })
}

pub fn (c &ConsoleSender) whitelist_enabled() bool {
	return c.hub.whitelist.is_enabled()
}

pub fn (c &ConsoleSender) whitelist_names() []string {
	return c.hub.whitelist.names_list()
}
