module session

import protocol
import protocol.types

fn test_build_sidebar_packets_sequence() {
	packets := build_sidebar_packets('Title', ['a', 'b', 'c'])
	// RemoveObjective, SetDisplayObjective, SetScore
	assert packets.len == 3

	remove := packets[0]
	if remove is protocol.RemoveObjectivePacket {
		assert remove.objective_name == sidebar_objective
	} else {
		assert false, 'packet 0 is not RemoveObjectivePacket'
	}

	display := packets[1]
	if display is protocol.SetDisplayObjectivePacket {
		assert display.display_slot == sidebar_slot
		assert display.objective_name == sidebar_objective
		assert display.display_name == 'Title'
		assert display.sort_order == 0
	} else {
		assert false, 'packet 1 is not SetDisplayObjectivePacket'
	}

	score := packets[2]
	if score is protocol.SetScorePacket {
		assert score.type == protocol.set_score_type_change
		assert score.entries.len == 3
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}

fn test_build_sidebar_packets_line_order_top_to_bottom() {
	packets := build_sidebar_packets('T', ['top', 'mid', 'bottom'])
	score := packets[2]
	if score is protocol.SetScorePacket {
		// Ascending sort with score = index means lines[0] gets the lowest score
		// and renders at the top, matching the slice order.
		assert score.entries[0].custom_name == 'top'
		assert score.entries[0].score == 0
		assert score.entries[1].custom_name == 'mid'
		assert score.entries[1].score == 1
		assert score.entries[2].custom_name == 'bottom'
		assert score.entries[2].score == 2
		for entry in score.entries {
			assert entry.type == types.score_entry_type_fake_player
			assert entry.objective_name == sidebar_objective
		}
		// Distinct scoreboard ids so the client keeps entries separate.
		assert score.entries[0].scoreboard_id != score.entries[1].scoreboard_id
		assert score.entries[1].scoreboard_id != score.entries[2].scoreboard_id
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}

fn test_build_sidebar_packets_empty_lines() {
	packets := build_sidebar_packets('Empty', [])
	assert packets.len == 3
	score := packets[2]
	if score is protocol.SetScorePacket {
		assert score.entries.len == 0
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}
