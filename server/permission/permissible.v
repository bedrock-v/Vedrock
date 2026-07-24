module permission

import sync

// Permissible is attached to a player-session (or console) and answers
// permission checks for it. An explicit override always wins; otherwise the permission's
// own default (granted / denied / op / not_op) decides based on whether this
// Permissible is currently operator.
//
// mutex guards is_op and overrides. Permission state is read by command checks
// and written by runtime op/admin commands, so callers must use the accessors
// below.
pub struct Permissible {
mut:
	mutex     &sync.Mutex = sync.new_mutex()
	is_op     bool
	overrides map[string]bool
}

pub fn (p &Permissible) op() bool {
	mut m := p.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.is_op
}

pub fn (mut p Permissible) set_op(op bool) {
	p.mutex.lock()
	p.is_op = op
	p.mutex.unlock()
}

// has_permission checks name against any explicit override first, then
// falls back to the permission's registered default.
pub fn (p &Permissible) has_permission(name string) bool {
	mut m := p.mutex
	m.lock()
	defer {
		m.unlock()
	}
	if name in p.overrides {
		return p.overrides[name]
	}
	perm := lookup(name)
	return match perm.default {
		.granted { true }
		.denied { false }
		.op { p.is_op }
		.not_op { !p.is_op }
	}
}

pub fn (mut p Permissible) set_permission(name string, value bool) {
	p.mutex.lock()
	p.overrides[name] = value
	p.mutex.unlock()
}

pub fn (mut p Permissible) unset_permission(name string) {
	p.mutex.lock()
	p.overrides.delete(name)
	p.mutex.unlock()
}
