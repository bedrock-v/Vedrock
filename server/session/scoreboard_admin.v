module session

import server.cmd
import server.player.scoreboard

// The Sender side of the scoreboard: every one of these reads or writes the
// server-wide registry on the Hub and redraws whatever slot the change was
// visible in.

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

fn (mut s NetworkSession) scoreboard_teams() []cmd.TeamInfo {
	return s.hub.team_infos()
}

fn (mut s NetworkSession) scoreboard_add_team(name string, display_name string) bool {
	return s.hub.add_team(name, display_name)
}

fn (mut s NetworkSession) scoreboard_remove_team(name string) bool {
	return s.hub.remove_team(name)
}

fn (mut s NetworkSession) scoreboard_team_join(team string, entry string) bool {
	return s.hub.team_join(team, entry)
}

fn (mut s NetworkSession) scoreboard_team_leave(entry string) bool {
	return s.hub.team_leave(entry)
}

fn (mut s NetworkSession) scoreboard_team_option(team string, option string, value string) bool {
	return s.hub.team_option(team, option, value)
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
	if !h.scoreboards.remove_objective(name) {
		return false
	}
	h.refresh_displays()
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
	h.refresh_displays()
	return true
}

pub fn (mut h Hub) add_score(objective string, entry string, delta int) ?int {
	updated := h.scoreboards.add_score(objective, entry, delta) or { return none }
	h.refresh_displays()
	return updated
}

pub fn (mut h Hub) reset_score(entry string) {
	h.scoreboards.reset_score('', entry)
	h.refresh_displays()
}

pub fn (h &Hub) team_infos() []cmd.TeamInfo {
	mut out := []cmd.TeamInfo{}
	for team in h.scoreboards.teams() {
		out << cmd.TeamInfo{
			name:         team.name
			display_name: team.display_title()
			members:      h.scoreboards.members(team.name).len
		}
	}
	return out
}

pub fn (mut h Hub) add_team(name string, display_name string) bool {
	if name == '' {
		return false
	}
	return h.scoreboards.add_team(scoreboard.Team{
		name:         name
		display_name: display_name
	})
}

pub fn (mut h Hub) remove_team(name string) bool {
	members := h.scoreboards.members(name)
	if !h.scoreboards.remove_team(name) {
		return false
	}
	h.refresh_name_tags(members)
	return true
}

pub fn (mut h Hub) team_join(team string, entry string) bool {
	if !h.scoreboards.join_team(team, entry) {
		return false
	}
	h.refresh_name_tags([entry])
	return true
}

pub fn (mut h Hub) team_leave(entry string) bool {
	if !h.scoreboards.leave_team(entry) {
		return false
	}
	h.refresh_name_tags([entry])
	return true
}

// team_option sets one of a team's settings from the names the command uses.
pub fn (mut h Hub) team_option(name string, option string, value string) bool {
	team := h.scoreboards.team(name) or { return false }
	updated := apply_team_option(team, option, value) or { return false }
	if !h.scoreboards.update_team(updated) {
		return false
	}
	h.refresh_name_tags(h.scoreboards.members(name))
	return true
}

fn apply_team_option(team scoreboard.Team, option string, value string) ?scoreboard.Team {
	return match option.to_lower() {
		'color', 'colour' {
			scoreboard.Team{
				...team
				colour: value
			}
		}
		'prefix' {
			scoreboard.Team{
				...team
				prefix: value
			}
		}
		'suffix' {
			scoreboard.Team{
				...team
				suffix: value
			}
		}
		'friendlyfire' {
			scoreboard.Team{
				...team
				friendly_fire: parse_option_flag(value)?
			}
		}
		'nametagvisibility' {
			scoreboard.Team{
				...team
				name_tag_visible: scoreboard.name_tag_visibility_from_name(value)?
			}
		}
		else {
			none
		}
	}
}

fn parse_option_flag(value string) ?bool {
	return match value.to_lower() {
		'true' { true }
		'false' { false }
		else { none }
	}
}

// refresh_name_tags resends the name of every listed player, so a team's
// colour and prefix appear without them having to reconnect.
fn (mut h Hub) refresh_name_tags(names []string) {
	for name in names {
		mut target := h.session_by_name(name) or { continue }
		h.broadcast(target.set_actor_data())
	}
}
