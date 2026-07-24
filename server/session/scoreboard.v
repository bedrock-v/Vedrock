module session

import protocol
import protocol.types

// sidebar_objective is the stable objective name used for the per-player
// sidebar scoreboard. Reusing one name means re-showing cleanly replaces the
// previous board instead of stacking objectives.
const sidebar_objective = 'vedrock.sidebar'
const sidebar_slot = 'sidebar'

// build_sidebar_packets returns the packet sequence that renders a sidebar
// scoreboard with the given title and lines. Factored out as a pure function so
// the protocol wiring can be unit-tested without a live connection.
//
// Bedrock renders sidebar lines as fake-player entries ordered by their score.
// We use ascending sort (sort_order 0) and assign score = line index, so
// lines[0] has the lowest score and sits at the top - matching the slice order.
// Each entry needs a distinct scoreboard_id or the client collapses them.
fn build_sidebar_packets(title string, lines []string) []protocol.Packet {
	mut packets := []protocol.Packet{cap: lines.len + 2}
	// Drop any previous board first so re-showing replaces cleanly.
	packets << &protocol.RemoveObjectivePacket{
		objective_name: sidebar_objective
	}
	packets << &protocol.SetDisplayObjectivePacket{
		display_slot:   sidebar_slot
		objective_name: sidebar_objective
		display_name:   title
		criteria_name:  'dummy'
		sort_order:     0
	}
	mut entries := []types.ScorePacketEntry{cap: lines.len}
	for i, line in lines {
		entries << types.ScorePacketEntry{
			scoreboard_id:  i64(i + 1)
			objective_name: sidebar_objective
			score:          i
			type:           types.score_entry_type_fake_player
			custom_name:    line
		}
	}
	packets << &protocol.SetScorePacket{
		type:    protocol.set_score_type_change
		entries: entries
	}
	return packets
}

// show_scoreboard replaces the player's sidebar with the supplied title
// and lines. Packets are queued so remote command calls do not block here.
pub fn (mut s NetworkSession) show_scoreboard(title string, lines []string) {
	for p in build_sidebar_packets(title, lines) {
		s.deliver(p)
	}
}

pub fn (mut s NetworkSession) clear_scoreboard() {
	s.deliver(&protocol.RemoveObjectivePacket{
		objective_name: sidebar_objective
	})
}
