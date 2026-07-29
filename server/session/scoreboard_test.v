module session

import protocol.version.v662.enums as enums_662
import protocol.version.v662.packets as packets_662
import protocol.version.v662.types as types_662

fn score_change_entries(action packets_662.SetScoreAction) []packets_662.ScorePacketInfoChangeEntry {
	match action {
		packets_662.SetScoreChange {
			return action.entries
		}
		packets_662.SetScoreRemove {
			return []packets_662.ScorePacketInfoChangeEntry{}
		}
	}
}

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
	if score is packets_662.SetScorePacket {
		entries := score_change_entries(score.action)
		assert entries.len == 3
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}

fn test_build_sidebar_packets_line_order_top_to_bottom() {
	packets := build_sidebar_packets('T', ['top', 'mid', 'bottom'])
	score := packets[2]
	if score is packets_662.SetScorePacket {
		entries := score_change_entries(score.action)
		// Ascending sort with score = index means lines[0] gets the lowest score
		// and renders at the top, matching the slice order.
		assert entries[0].identity_definition_type is types_662.IdentityFakePlayer
		assert entries[0].identity_definition_type.fake_player_name == 'top'
		assert entries[0].score_value == 0
		assert entries[1].identity_definition_type is types_662.IdentityFakePlayer
		assert entries[1].identity_definition_type.fake_player_name == 'mid'
		assert entries[1].score_value == 1
		assert entries[2].identity_definition_type is types_662.IdentityFakePlayer
		assert entries[2].identity_definition_type.fake_player_name == 'bottom'
		assert entries[2].score_value == 2
		for entry in entries {
			assert entry.objective_name == sidebar_objective
		}
		// Distinct scoreboard ids so the client keeps entries separate.
		assert entries[0].id.id != entries[1].id.id
		assert entries[1].id.id != entries[2].id.id
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}

fn test_build_sidebar_packets_empty_lines() {
	packets := build_sidebar_packets('Empty', [])
	assert packets.len == 3
	score := packets[2]
	if score is packets_662.SetScorePacket {
		entries := score_change_entries(score.action)
		assert entries.len == 0
	} else {
		assert false, 'packet 2 is not SetScorePacket'
	}
}
