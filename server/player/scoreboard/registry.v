module scoreboard

import sync

// Registry holds the objectives, scores and teams of one server. It is shared
// across sessions, so every read and write goes through its own lock.
@[heap]
pub struct Registry {
mut:
	mutex      &sync.Mutex = sync.new_mutex()
	objectives map[string]Objective
	// scores is per objective name, then per entry name. An entry is a player
	// name or any other label an objective counts.
	scores   map[string]map[string]int
	displays map[string]string
	teams    map[string]Team
	// membership maps an entry name to the team it is in, so the common
	// lookup does not have to scan every team.
	membership map[string]string
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

// remove_objective drops an objective, its scores and any slot showing it.
pub fn (mut r Registry) remove_objective(name string) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if name !in r.objectives {
		return false
	}
	r.objectives.delete(name)
	r.scores.delete(name)
	for slot, shown in r.displays.clone() {
		if shown == name {
			r.displays.delete(slot)
		}
	}
	return true
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

// add_team registers a team, reporting false when one already goes by that
// name.
pub fn (mut r Registry) add_team(team Team) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if team.name in r.teams {
		return false
	}
	r.teams[team.name] = team
	return true
}

// remove_team drops a team and empties it.
pub fn (mut r Registry) remove_team(name string) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if name !in r.teams {
		return false
	}
	r.teams.delete(name)
	for entry, team in r.membership.clone() {
		if team == name {
			r.membership.delete(entry)
		}
	}
	return true
}

// update_team replaces a team's settings, keeping its members.
pub fn (mut r Registry) update_team(team Team) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if team.name !in r.teams {
		return false
	}
	r.teams[team.name] = team
	return true
}

pub fn (r &Registry) team(name string) ?Team {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return r.teams[name] or { return none }
}

pub fn (r &Registry) teams() []Team {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := []Team{cap: r.teams.len}
	for _, team in r.teams {
		out << team
	}
	return out
}

// join_team moves an entry into a team, leaving whichever it was in.
pub fn (mut r Registry) join_team(team_name string, entry string) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if team_name !in r.teams {
		return false
	}
	r.membership[entry] = team_name
	return true
}

// leave_team takes an entry out of whatever team it is in.
pub fn (mut r Registry) leave_team(entry string) bool {
	r.mutex.lock()
	defer {
		r.mutex.unlock()
	}
	if entry !in r.membership {
		return false
	}
	r.membership.delete(entry)
	return true
}

// team_of returns the team an entry belongs to.
pub fn (r &Registry) team_of(entry string) ?Team {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	name := r.membership[entry] or { return none }
	return r.teams[name] or { return none }
}

// members lists who is in a team.
pub fn (r &Registry) members(team_name string) []string {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := []string{}
	for entry, name in r.membership {
		if name == team_name {
			out << entry
		}
	}
	return out
}

// same_team reports whether two entries share a team. Two entries in no team
// are not on the same team.
pub fn (r &Registry) same_team(a string, b string) bool {
	mut m := r.mutex
	m.lock()
	defer {
		m.unlock()
	}
	first := r.membership[a] or { return false }
	second := r.membership[b] or { return false }
	return first == second
}
