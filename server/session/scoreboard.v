module session

import bedrock_v.protocol
import bedrock_v.protocol.current as proto
import server.player.scoreboard
import server.player

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
	packets << &proto.RemoveObjectivePacket{
		objective_name: sidebar_objective
	}
	packets << &proto.SetDisplayObjectivePacket{
		display_slot_name:      sidebar_slot
		objective_name:         sidebar_objective
		objective_display_name: title
		criteria_name:          'dummy'
		sort_order:             proto.ObjectiveSortOrder.ascending
	}
	mut entries := proto.ScorePacketEntries{}
	for i, line in lines {
		entries << proto.ScoreEntryChangeFakePlayer{
			scoreboard_id:    proto.ScoreboardId{
				id: i64(i + 1)
			}
			objective_name:   sidebar_objective
			score_value:      i32(i)
			fake_player_name: line
		}
	}
	packets << &proto.SetScorePacket{
		score_info: entries
	}
	return packets
}

// show_scoreboard replaces the player's sidebar with the supplied title
// and lines. Packets are queued so remote command calls do not block here.
fn (mut s NetworkSession) show_scoreboard(title string, lines []string) {
	for p in build_sidebar_packets(title, lines) {
		s.deliver(p)
	}
}

// send_scoreboard renders board on the player's sidebar, replacing whichever
// board was shown before. Editing a board after sending it does not update the
// sidebar: send it again.
fn (mut s NetworkSession) send_scoreboard(board &scoreboard.Scoreboard) {
	s.show_scoreboard(board.name(), board.lines())
}

fn (mut s NetworkSession) remove_scoreboard() {
	s.deliver(&proto.RemoveObjectivePacket{
		objective_name: sidebar_objective
	})
}
