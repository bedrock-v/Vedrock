module permission

// Permissible is attached to a player-session (or console) and answers
// permission checks for it. An explicit override always wins; otherwise the permission's 
// own default (granted / denied / op / not_op) decides based on whether this
// Permissible is currently operator.
pub struct Permissible {
mut:
	is_op     bool
	overrides map[string]bool
}

pub fn (p &Permissible) op() bool {
	return p.is_op
}

pub fn (mut p Permissible) set_op(op bool) {
	p.is_op = op
}

// has_permission checks name against any explicit override first, then
// falls back to the permission's registered default.
pub fn (p &Permissible) has_permission(name string) bool {
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
	p.overrides[name] = value
}

pub fn (mut p Permissible) unset_permission(name string) {
	p.overrides.delete(name)
}
