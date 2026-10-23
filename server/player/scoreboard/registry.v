module scoreboard

import sync

// Registry holds the objectives and scores of one server. It is shared across
// sessions, so every read and write goes through its own lock.
@[heap]
pub struct Registry {
mut:
	mutex      &sync.Mutex = sync.new_mutex()
	objectives map[string]Objective
	// scores is per objective name, then per entry name. An entry is a player
	// name or any other label an objective counts.
	scores   map[string]map[string]int
	displays map[string]string
	// entry_ids gives every entry the one scoreboard id the client knows it by.
	// yeah, it has to stay the same for the entry's whole life, otherwise a
	// score update or a reset can't name the line it is changing.
	entry_ids     map[string]i64
	next_entry_id i64
}

pub fn new_registry() &Registry {
	return &Registry{}
}

// add_objective registers an objective, reporting false when one already goes
// by that name.
pub fn (mut r Registry) add_objective(objective Objective) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if objective.name in r.objectives {
		return false
	}
	r.objectives[objective.name] = objective
	return true
}

// remove_objective drops an objective, its scores and any slot showing it,
// and returns the slots it cleared so only those need redrawing. none means
// there was no such objective.
pub fn (mut r Registry) remove_objective(name string) ?[]DisplaySlot {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if name !in r.objectives {
		return none
	}
	r.objectives.delete(name)
	r.scores.delete(name)
	mut cleared := []DisplaySlot{}
	for slot in all_display_slots {
		if r.displays[slot.wire_name()] or { '' } == name {
			r.displays.delete(slot.wire_name())
			cleared << slot
		}
	}
	return cleared
}

pub fn (r &Registry) objective(name string) ?Objective {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return r.objectives[name] or { return none }
}

pub fn (r &Registry) objectives() []Objective {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := []Objective{cap: r.objectives.len}
	for _, objective in r.objectives {
		out << objective
	}
	return out
}

// set_display shows an objective in a slot. An unknown objective clears the
// slot instead, which is what an empty name means.
pub fn (mut r Registry) set_display(slot DisplaySlot, objective_name string) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	key := slot.wire_name()
	if objective_name == '' {
		r.displays.delete(key)
		return true
	}
	if objective_name !in r.objectives {
		return false
	}
	r.displays[key] = objective_name
	return true
}

pub fn (r &Registry) display(slot DisplaySlot) ?string {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return r.displays[slot.wire_name()] or { return none }
}

// slots_showing lists the slots an objective is drawn in, which is everywhere
// a change to one of its scores has to reach.
pub fn (r &Registry) slots_showing(objective_name string) []DisplaySlot {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := []DisplaySlot{}
	for slot in all_display_slots {
		if r.displays[slot.wire_name()] or { '' } == objective_name {
			out << slot
		}
	}
	return out
}

// entry_id is the scoreboard id of an entry that has been scored at least once.
pub fn (r &Registry) entry_id(entry string) ?i64 {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return r.entry_ids[entry] or { return none }
}

// assign_entry_id must be called with the lock held.
fn (mut r Registry) assign_entry_id(entry string) {
	if entry !in r.entry_ids {
		r.next_entry_id++
		r.entry_ids[entry] = r.next_entry_id
	}
}

// set_score records an entry's score under an objective, reporting false when
// the objective does not exist.
pub fn (mut r Registry) set_score(objective_name string, entry string, value int) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if objective_name !in r.objectives {
		return false
	}
	r.scores[objective_name][entry] = value
	r.assign_entry_id(entry)
	return true
}

// add_score moves an entry's score by delta and returns where it ended up.
pub fn (mut r Registry) add_score(objective_name string, entry string, delta int) ?int {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if objective_name !in r.objectives {
		return none
	}
	current := r.scores[objective_name][entry] or { 0 }
	updated := current + delta
	r.scores[objective_name][entry] = updated
	r.assign_entry_id(entry)
	return updated
}

// reset_score drops an entry from one objective, or from all of them when the
// objective name is empty.
pub fn (mut r Registry) reset_score(objective_name string, entry string) {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if objective_name == '' {
		for name, _ in r.scores {
			r.scores[name].delete(entry)
		}
		return
	}
	r.scores[objective_name].delete(entry)
}

pub fn (r &Registry) scores(objective_name string) map[string]int {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return (r.scores[objective_name] or {
		map[string]int{}
	}).clone()
}
