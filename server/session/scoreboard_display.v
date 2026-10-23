module session

import bedrock_v.protocol
import server.player.scoreboard
import bedrock_v.protocol.enums
import bedrock_v.protocol.packets
import bedrock_v.protocol.types

// Only setdisplay and a new viewer redraw a whole slot. A score change sends
// the one line that changed, and only for the slots showing its objective.
//
// The sidebar draws every entry as a fake player line. list and belowname hang
// the score off a player instead, so those entries name the player by the id
// the viewer knows them by and are skipped for anyone the viewer was never
// shown: there is nothing on their screen to attach the score to.

// display_objective_name is the objective name the client is given for a slot.
// Each slot gets its own so showing one does not disturb another, and none of
// them can collide with the per-player sidebar_objective.
fn display_objective_name(slot scoreboard.DisplaySlot) string {
	return 'vedrock.display.${slot.wire_name()}'
}

// score_entry is how one entry of a slot reads to viewer, or none when the
// viewer has nothing to show it against.
fn (mut h Hub) score_entry(mut viewer NetworkSession, slot scoreboard.DisplaySlot, entry string, value int) ?packets.ScorePacketEntry {
	id := h.scoreboards.entry_id(entry) or { return none }
	if slot == .sidebar {
		return packets.ScoreEntryChangeFakePlayer{
			scoreboard_id:    types.ScoreboardId{
				id: id
			}
			objective_name:   display_objective_name(slot)
			score_value:      i32(value)
			fake_player_name: entry
		}
	}
	target := h.session_by_name(entry) or { return none }
	wire_id := viewer.known_wire_id(target.runtime_id) or { return none }
	return packets.ScoreEntryChangePlayer{
		scoreboard_id:    types.ScoreboardId{
			id: id
		}
		objective_name:   display_objective_name(slot)
		score_value:      i32(value)
		player_unique_id: i64(wire_id)
	}
}

// slot_packets is the packet sequence that draws one objective in one slot for
// one viewer.
fn (mut h Hub) slot_packets(mut viewer NetworkSession, slot scoreboard.DisplaySlot, objective scoreboard.Objective) []protocol.Packet {
	scores := h.scoreboards.scores(objective.name)
	name := display_objective_name(slot)
	mut batch := []protocol.Packet{cap: 3}
	batch << &packets.RemoveObjectivePacket{
		objective_name: name
	}
	batch << &packets.SetDisplayObjectivePacket{
		display_slot_name:      slot.wire_name()
		objective_name:         name
		objective_display_name: objective.display_title()
		criteria_name:          'dummy'
		sort_order:             if objective.descending {
			enums.ObjectiveSortOrder.descending
		} else {
			enums.ObjectiveSortOrder.ascending
		}
	}
	mut entries := []packets.ScorePacketEntry{cap: scores.len}
	for entry, value in scores {
		entries << h.score_entry(mut viewer, slot, entry, value) or { continue }
	}
	if entries.len > 0 {
		batch << &packets.SetScorePacket{
			score_info: entries
		}
	}
	return batch
}

// draw_slot sends viewer whatever a slot is showing, or clears it when the
// slot shows nothing.
fn (mut h Hub) draw_slot(mut viewer NetworkSession, slot scoreboard.DisplaySlot) {
	objective_name := h.scoreboards.display(slot) or {
		viewer.deliver(&packets.RemoveObjectivePacket{
			objective_name: display_objective_name(slot)
		})
		return
	}
	objective := h.scoreboards.objective(objective_name) or { return }
	for p in h.slot_packets(mut viewer, slot, objective) {
		viewer.deliver(p)
	}
}

// broadcast_display redraws one slot for everyone, which only setdisplay
// needs.
fn (mut h Hub) broadcast_display(slot scoreboard.DisplaySlot) {
	for mut viewer in h.snapshot() {
		h.draw_slot(mut viewer, slot)
	}
}

// clear_slots takes slots off everyone's screen, after the objective they
// showed went away.
fn (mut h Hub) clear_slots(slots []scoreboard.DisplaySlot) {
	if slots.len == 0 {
		return
	}
	for mut viewer in h.snapshot() {
		for slot in slots {
			viewer.deliver(&packets.RemoveObjectivePacket{
				objective_name: display_objective_name(slot)
			})
		}
	}
}

// send_score_change pushes one entry's new score to the slots showing its
// objective.
fn (mut h Hub) send_score_change(objective string, entry string, value int) {
	slots := h.scoreboards.slots_showing(objective)
	if slots.len == 0 {
		return
	}
	for mut viewer in h.snapshot() {
		mut entries := []packets.ScorePacketEntry{cap: slots.len}
		for slot in slots {
			entries << h.score_entry(mut viewer, slot, entry, value) or { continue }
		}
		if entries.len > 0 {
			viewer.deliver(&packets.SetScorePacket{
				score_info: entries
			})
		}
	}
}

// send_score_reset takes an entry's line out of every slot. Removing a line the
// viewer never had is a noop on the client, so this does not bother checking.
fn (mut h Hub) send_score_reset(entry string) {
	id := h.scoreboards.entry_id(entry) or { return }
	mut entries := []packets.ScorePacketEntry{}
	for slot in scoreboard.all_display_slots {
		if _ := h.scoreboards.display(slot) {
			entries << packets.ScoreEntryRemove{
				scoreboard_id:  types.ScoreboardId{
					id: id
				}
				objective_name: display_objective_name(slot)
			}
		}
	}
	if entries.len == 0 {
		return
	}
	// hmm, a remove names no actor, so unlike the other score packets this one
	// really is the same for every viewer.
	h.broadcast(&packets.SetScorePacket{
		score_info: entries
	})
}

// sync_scoreboard_for brings a session up to date after it joined or changed
// worlds. The session gets every slot drawn from scratch, since a world change
// threw away the ids its old lines named players by. Everyone else gets this
// player's own list and belowname lines, which they could not be shown before
// they knew the player.
fn (mut h Hub) sync_scoreboard_for(mut s NetworkSession) {
	for slot in scoreboard.all_display_slots {
		if _ := h.scoreboards.display(slot) {
			h.draw_slot(mut s, slot)
		}
	}
	name := s.player.identity.display_name
	for slot in [scoreboard.DisplaySlot.list, .belowname] {
		objective := h.scoreboards.display(slot) or { continue }
		value := h.scoreboards.scores(objective)[name] or { continue }
		for mut viewer in h.snapshot() {
			if viewer.runtime_id == s.runtime_id {
				continue
			}
			entry := h.score_entry(mut viewer, slot, name, value) or { continue }
			viewer.deliver(&packets.SetScorePacket{
				score_info: [entry]
			})
		}
	}
}
