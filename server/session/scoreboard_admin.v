module session

import server.cmd
import server.player.scoreboard

// The Sender side of the scoreboard: every one of these reads or writes the
// server-wide registry on the Hub and sends whatever part of a slot the change
// was visible in.

fn (mut s NetworkSession) scoreboard_objectives() []cmd.ObjectiveInfo {
	return s.hub.objective_infos()
}

fn (mut s NetworkSession) scoreboard_add_objective(name string, display_name string) bool {
	return s.hub.add_objective(name, display_name)
}

fn (mut s NetworkSession) scoreboard_remove_objective(name string) bool {
	return s.hub.remove_objective(name)
}

fn (mut s NetworkSession) scoreboard_set_display(slot string, objective string) bool {
	return s.hub.set_display(slot, objective)
}

fn (mut s NetworkSession) scoreboard_set_score(objective string, entry string, value int) bool {
	return s.hub.set_score(objective, entry, value)
}

fn (mut s NetworkSession) scoreboard_add_score(objective string, entry string, delta int) ?int {
	return s.hub.add_score(objective, entry, delta)
}

fn (mut s NetworkSession) scoreboard_reset_score(entry string) {
	s.hub.reset_score(entry)
}

// Hub owns the registry; the session methods above are only the route in.

pub fn (h &Hub) objective_infos() []cmd.ObjectiveInfo {
	mut out := []cmd.ObjectiveInfo{}
	for objective in h.scoreboards.objectives() {
		out << cmd.ObjectiveInfo{
			name:         objective.name
			display_name: objective.display_title()
		}
	}
	return out
}

pub fn (mut h Hub) add_objective(name string, display_name string) bool {
	if name == '' {
		return false
	}
	return h.scoreboards.add_objective(scoreboard.Objective{
		name:         name
		display_name: display_name
	})
}

pub fn (mut h Hub) remove_objective(name string) bool {
	cleared := h.scoreboards.remove_objective(name) or { return false }
	h.clear_slots(cleared)
	return true
}

pub fn (mut h Hub) set_display(slot_name string, objective string) bool {
	slot := scoreboard.display_slot_from_name(slot_name) or { return false }
	if !h.scoreboards.set_display(slot, objective) {
		return false
	}
	h.broadcast_display(slot)
	return true
}

pub fn (mut h Hub) set_score(objective string, entry string, value int) bool {
	if !h.scoreboards.set_score(objective, entry, value) {
		return false
	}
	h.send_score_change(objective, entry, value)
	return true
}

pub fn (mut h Hub) add_score(objective string, entry string, delta int) ?int {
	updated := h.scoreboards.add_score(objective, entry, delta) or { return none }
	h.send_score_change(objective, entry, updated)
	return updated
}

pub fn (mut h Hub) reset_score(entry string) {
	h.scoreboards.reset_score('', entry)
	h.send_score_reset(entry)
}
