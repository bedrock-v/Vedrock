module effect

pub struct TickResult {
pub:
	active  []Effect
	expired []Effect
}

pub struct AddResult {
pub:
	effect   Effect
	accepted bool
	stored   bool
	replaced bool
	previous Effect
}

pub struct Manager {
mut:
	effects map[int]Effect
}

pub fn new_manager() Manager {
	return Manager{
		effects: map[int]Effect{}
	}
}

pub fn (mut m Manager) add(e Effect) Effect {
	return m.add_result(e).effect
}

pub fn (mut m Manager) add_result(e Effect) AddResult {
	if e.level() <= 0 {
		panic('effect level must be greater than zero')
	}
	if e.duration_ticks() < 0 && !e.infinite() {
		panic('effect duration cannot be negative')
	}
	if e.instant() || !e.effect_type().lasting {
		return AddResult{
			effect:   e
			accepted: true
		}
	}
	existing := m.effects[e.effect_type().id] or {
		m.effects[e.effect_type().id] = e
		return AddResult{
			effect:   e
			accepted: true
			stored:   true
		}
	}
	if existing.level() > e.level() {
		return AddResult{
			effect: existing
			stored: true
		}
	}
	if existing.level() == e.level() {
		if existing.infinite() {
			return AddResult{
				effect: existing
				stored: true
			}
		}
		if !e.infinite() && existing.duration_ticks() > e.duration_ticks() {
			return AddResult{
				effect: existing
				stored: true
			}
		}
	}
	m.effects[e.effect_type().id] = e
	return AddResult{
		effect:   e
		accepted: true
		stored:   true
		replaced: true
		previous: existing
	}
}

pub fn (mut m Manager) remove(typ Type) ?Effect {
	e := m.effects[typ.id] or { return none }
	m.effects.delete(typ.id)
	return e
}

pub fn (m &Manager) effect(typ Type) ?Effect {
	return m.effects[typ.id] or { return none }
}

pub fn (m &Manager) effects() []Effect {
	mut out := []Effect{cap: m.effects.len}
	for _, e in m.effects {
		out << e
	}
	return out
}

pub fn (mut m Manager) tick() TickResult {
	mut active := []Effect{}
	mut expired := []Effect{}
	for id, e in m.effects {
		if e.expired() {
			expired << e
			m.effects.delete(id)
			continue
		}
		active << e
		m.effects[id] = e.tick_duration()
	}
	return TickResult{
		active:  active
		expired: expired
	}
}
