module session

import bedrock_v.protocol.current as proto

fn test_build_sidebar_packets_sequence() {
	packets := build_sidebar_packets('Title', ['a', 'b', 'c'])
	// RemoveObjective, SetDisplayObjective, SetScore
	assert packets.len == 3

	remove := packets[0]
	if remove is proto.RemoveObjectivePacket {
		assert remove.objective_name == sidebar_objective
	} else {
		assert false, 'packet 0 is not RemoveObjectivePacket'
	}

	display := packets[1]
	if display is proto.SetDisplayObjectivePacket {
		assert display.display_slot_name == sidebar_slot
		assert display.objective_name == sidebar_objective
		assert display.objective_display_name == 'Title'
		assert display.sort_order == proto.ObjectiveSortOrder.ascending
	} else {
		assert false, 'packet 1 is not SetDisplayObjectivePacket'
	}

	score := packets[2]
	if score is proto.SetScorePacket {
		assert score.score_info.len == 3
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}

fn test_build_sidebar_packets_line_order_top_to_bottom() {
	packets := build_sidebar_packets('T', ['top', 'mid', 'bottom'])
	score := packets[2]
	if score is proto.SetScorePacket {
		entries := score.score_info
		// Ascending sort with score = index means lines[0] gets the lowest score
		// and renders at the top, matching the slice order.
		e0 := entries[0]
		e1 := entries[1]
		e2 := entries[2]
		if entry0 := proto.score_entry_change_fake_player(e0) {
			assert entry0.fake_player_name == 'top'
			assert entry0.score_value == 0
			assert entry0.objective_name == sidebar_objective
		} else {
			assert false, 'entry 0 is not ScoreEntryChangeFakePlayer'
		}
		if entry1 := proto.score_entry_change_fake_player(e1) {
			assert entry1.fake_player_name == 'mid'
			assert entry1.score_value == 1
			assert entry1.objective_name == sidebar_objective
		} else {
			assert false, 'entry 1 is not ScoreEntryChangeFakePlayer'
		}
		if entry2 := proto.score_entry_change_fake_player(e2) {
			assert entry2.fake_player_name == 'bottom'
			assert entry2.score_value == 2
			assert entry2.objective_name == sidebar_objective
		} else {
			assert false, 'entry 2 is not ScoreEntryChangeFakePlayer'
		}
		// Distinct scoreboard ids so the client keeps entries separate.
		if first := proto.score_entry_change_fake_player(e0) {
			if second := proto.score_entry_change_fake_player(e1) {
				assert first.scoreboard_id.id != second.scoreboard_id.id
			}
		}
		if second := proto.score_entry_change_fake_player(e1) {
			if third := proto.score_entry_change_fake_player(e2) {
				assert second.scoreboard_id.id != third.scoreboard_id.id
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
	if score is proto.SetScorePacket {
		assert score.score_info.len == 0
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}
