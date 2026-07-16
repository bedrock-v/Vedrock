module session

import server.internal.logger

struct WhitelistAddJob {
	name string
	log  &logger.Logger = unsafe { nil }
}

fn (j WhitelistAddJob) run(mut h Hub) {
	h.whitelist.add(j.name) or {
		if !isnil(j.log) {
			j.log.warn('Failed to persist whitelist add for ${j.name}: ${err}')
		}
	}
}

struct WhitelistRemoveJob {
	name string
	log  &logger.Logger = unsafe { nil }
}

fn (j WhitelistRemoveJob) run(mut h Hub) {
	h.whitelist.remove(j.name) or {
		if !isnil(j.log) {
			j.log.warn('Failed to persist whitelist remove for ${j.name}: ${err}')
		}
	}
}

struct WhitelistSetEnabledJob {
	value bool
	log   &logger.Logger = unsafe { nil }
}

fn (j WhitelistSetEnabledJob) run(mut h Hub) {
	h.whitelist.set_enabled(j.value) or {
		if !isnil(j.log) {
			j.log.warn('Failed to persist whitelist enabled=${j.value}: ${err}')
		}
	}
}

pub fn (mut s NetworkSession) whitelist_add(name string) {
	s.hub.submit(WhitelistAddJob{
		name: name
		log:  s.log
	})
}

pub fn (mut s NetworkSession) whitelist_remove(name string) {
	s.hub.submit(WhitelistRemoveJob{
		name: name
		log:  s.log
	})
}

pub fn (mut s NetworkSession) whitelist_set_enabled(value bool) {
	s.hub.submit(WhitelistSetEnabledJob{
		value: value
		log:   s.log
	})
}

pub fn (s &NetworkSession) whitelist_enabled() bool {
	return s.hub.whitelist.is_enabled()
}

pub fn (s &NetworkSession) whitelist_names() []string {
	return s.hub.whitelist.names_list()
}

pub fn (mut c ConsoleSender) whitelist_add(name string) {
	c.hub.submit(WhitelistAddJob{
		name: name
		log:  c.log
	})
}

pub fn (mut c ConsoleSender) whitelist_remove(name string) {
	c.hub.submit(WhitelistRemoveJob{
		name: name
		log:  c.log
	})
}

pub fn (mut c ConsoleSender) whitelist_set_enabled(value bool) {
	c.hub.submit(WhitelistSetEnabledJob{
		value: value
		log:   c.log
	})
}

pub fn (c &ConsoleSender) whitelist_enabled() bool {
	return c.hub.whitelist.is_enabled()
}

pub fn (c &ConsoleSender) whitelist_names() []string {
	return c.hub.whitelist.names_list()
}
