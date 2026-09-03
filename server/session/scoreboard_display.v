module session

import bedrock_v.protocol
import bedrock_v.protocol.current as proto
import server.player.scoreboard

// broadcast_display sends whatever a slot is showing to everyone, or clears it
// when the slot shows nothing. It is the one place a display slot is drawn, so
// sidebar, list and belowname all render the same way.
fn (mut h Hub) broadcast_display(slot scoreboard.DisplaySlot) {
	objective_name := h.scoreboards.display(slot) or {
		h.broadcast(&proto.RemoveObjectivePacket{
			objective_name: slot_objective_name(slot)
		})
		return
	}
	objective := h.scoreboards.objective(objective_name) or { return }
	for p in h.display_packets(slot, objective) {
		h.broadcast(p)
	}
}

// display_packets is the packet sequence that draws one objective in one slot.
// Built as its own function so the wiring can be tested without a connection.
fn (h &Hub) display_packets(slot scoreboard.DisplaySlot, objective scoreboard.Objective) []protocol.Packet {
	scores := h.scoreboards.scores(objective.name)
	name := slot_objective_name(slot)
	mut packets := []protocol.Packet{cap: scores.len + 2}
	packets << &proto.RemoveObjectivePacket{
		objective_name: name
	}
	packets << &proto.SetDisplayObjectivePacket{
		display_slot_name:      slot.wire_name()
		objective_name:         name
		objective_display_name: objective.display_title()
		criteria_name:          'dummy'
		sort_order:             if objective.descending {
			proto.ObjectiveSortOrder.descending
		} else {
			proto.ObjectiveSortOrder.ascending
		}
	}
	mut entries := proto.ScorePacketEntries{}
	mut id := i64(1)
	for entry, value in scores {
		entries << proto.ScoreEntryChangeFakePlayer{
			scoreboard_id:    proto.ScoreboardId{
				id: id
			}
			objective_name:   name
			score_value:      i32(value)
			fake_player_name: entry
		}
		id++
	}
	packets << &proto.SetScorePacket{
		score_info: entries
	}
	return packets
}

// slot_objective_name is the objective name the client is given for a slot.
// Each slot gets its own so showing one does not disturb another.
fn slot_objective_name(slot scoreboard.DisplaySlot) string {
	return 'vedrock.${slot.wire_name()}'
}

// refresh_displays redraws every slot that is showing something, which is what
// a score change or a new objective needs.
fn (mut h Hub) refresh_displays() {
	for slot in [scoreboard.DisplaySlot.sidebar, .list, .belowname] {
		h.broadcast_display(slot)
	}
}

// team_display_name is a player's name as their team says it should be shown,
// or their plain name when they are in no team.
fn (h &Hub) team_display_name(name string) string {
	team := h.scoreboards.team_of(name) or { return name }
	return team.decorate(name)
}

// friendly_fire_allowed reports whether one player's hit lands on another. Two
// players on a team that has friendly fire turned off cannot hurt each other.
fn (h &Hub) friendly_fire_allowed(attacker string, victim string) bool {
	if attacker == victim {
		return true
	}
	team := h.scoreboards.team_of(attacker) or { return true }
	if !h.scoreboards.same_team(attacker, victim) {
		return true
	}
	return team.friendly_fire
}

// shown_name is the name other players see for this session: decorated by the
// player's team when there is a server to ask, and the plain name otherwise.
fn (s &NetworkSession) shown_name() string {
	if isnil(s.hub) {
		return s.player.identity.display_name
	}
	return s.hub.team_display_name(s.player.identity.display_name)
}
