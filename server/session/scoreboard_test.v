module session

import protocol.version.v662.enums as enums_662
import protocol.version.v662.packets as packets_662
import protocol.version.v2168.packets as packets_2168

fn test_build_sidebar_packets_sequence() {
	packets := build_sidebar_packets('Title', ['a', 'b', 'c'])
	// RemoveObjective, SetDisplayObjective, SetScore
	assert packets.len == 3

	remove := packets[0]
	if remove is packets_662.RemoveObjectivePacket {
		assert remove.objective_name == sidebar_objective
	} else {
		assert false, 'packet 0 is not RemoveObjectivePacket'
	}

	display := packets[1]
	if display is packets_662.SetDisplayObjectivePacket {
		assert display.display_slot_name == sidebar_slot
		assert display.objective_name == sidebar_objective
		assert display.objective_display_name == 'Title'
		assert display.sort_order == enums_662.ObjectiveSortOrder.ascending
	} else {
		assert false, 'packet 1 is not SetDisplayObjectivePacket'
	}

	score := packets[2]
	if score is packets_2168.SetScorePacket {
		assert score.score_info.len == 3
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}

fn test_build_sidebar_packets_line_order_top_to_bottom() {
	packets := build_sidebar_packets('T', ['top', 'mid', 'bottom'])
	score := packets[2]
	if score is packets_2168.SetScorePacket {
		entries := score.score_info
		// Ascending sort with score = index means lines[0] gets the lowest score
		// and renders at the top, matching the slice order.
		e0 := entries[0]
		e1 := entries[1]
		e2 := entries[2]
		if e0 is packets_2168.ScoreEntryChangeFakePlayer {
			assert e0.fake_player_name == 'top'
			assert e0.score_value == 0
			assert e0.objective_name == sidebar_objective
		} else {
			assert false, 'entry 0 is not ScoreEntryChangeFakePlayer'
		}
		if e1 is packets_2168.ScoreEntryChangeFakePlayer {
			assert e1.fake_player_name == 'mid'
			assert e1.score_value == 1
			assert e1.objective_name == sidebar_objective
		} else {
			assert false, 'entry 1 is not ScoreEntryChangeFakePlayer'
		}
		if e2 is packets_2168.ScoreEntryChangeFakePlayer {
			assert e2.fake_player_name == 'bottom'
			assert e2.score_value == 2
			assert e2.objective_name == sidebar_objective
		} else {
			assert false, 'entry 2 is not ScoreEntryChangeFakePlayer'
		}
		// Distinct scoreboard ids so the client keeps entries separate.
		if e0 is packets_2168.ScoreEntryChangeFakePlayer {
			if e1 is packets_2168.ScoreEntryChangeFakePlayer {
				assert e0.scoreboard_id.id != e1.scoreboard_id.id
			}
		}
		if e1 is packets_2168.ScoreEntryChangeFakePlayer {
			if e2 is packets_2168.ScoreEntryChangeFakePlayer {
				assert e1.scoreboard_id.id != e2.scoreboard_id.id
			}
		}
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}

fn test_build_sidebar_packets_empty_lines() {
	packets := build_sidebar_packets('Empty', [])
	assert packets.len == 3
	score := packets[2]
	if score is packets_2168.SetScorePacket {
		assert score.score_info.len == 0
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}
