module session

import bedrock_v.protocol.types
import server.effect
import server.player

fn validation_session(mode player.Gamemode) &NetworkSession {
	mut pl := player.new_player()
	pl.set_game_mode(mode)
	mut s := &NetworkSession{
		player:  pl
		spawned: true
	}
	s.player.reset_position(types.Vector3{0.0, 64.0, 0.0})
	return s
}

fn test_a_normal_step_is_accepted() {
	mut s := validation_session(.survival)
	assert s.validate_movement(types.Vector3{0.3, 64.0, 0.0}, 1000)
}

fn test_a_teleport_across_the_world_is_rejected() {
	mut s := validation_session(.survival)
	assert !s.validate_movement(types.Vector3{500.0, 64.0, 0.0}, 1000)
}

fn test_a_long_gap_earns_more_room() {
	mut s := validation_session(.survival)
	// One report at t=0 to start the clock, then one 500ms later: ten ticks of
	// walking is comfortably more than four blocks.
	s.validate_movement(types.Vector3{0.0, 64.0, 0.0}, 1000)
	assert s.validate_movement(types.Vector3{4.0, 64.0, 0.0}, 1500)
}

fn test_a_gap_cannot_be_banked_forever() {
	mut s := validation_session(.survival)
	s.validate_movement(types.Vector3{0.0, 64.0, 0.0}, 1000)
	// An hour of standing still does not buy a jump across the map.
	assert !s.validate_movement(types.Vector3{500.0, 64.0, 0.0}, 1000 + 3600 * 1000)
}

fn test_flying_is_allowed_to_move_faster() {
	mut survival := validation_session(.survival)
	mut creative := validation_session(.creative)
	target := types.Vector3{3.5, 64.0, 0.0}
	assert !survival.validate_movement(target, 1000)
	assert creative.validate_movement(target, 1000)
}

fn test_speed_widens_the_budget() {
	mut plain := validation_session(.survival)
	mut hasted := validation_session(.survival)
	hasted.player.add_effect_result(effect.new(effect.speed, 5, 600))
	target := types.Vector3{3.0, 64.0, 0.0}
	assert !plain.validate_movement(target, 1000)
	assert hasted.validate_movement(target, 1000)
}

fn test_falling_is_not_read_as_cheating() {
	mut s := validation_session(.survival)
	// Terminal velocity is about four blocks a tick, so a single report can
	// legitimately drop a long way.
	assert s.validate_movement(types.Vector3{0.0, 59.0, 0.0}, 1000)
	assert !s.validate_movement(types.Vector3{0.0, 0.0, 0.0}, 1010)
}

fn test_spectators_are_not_checked() {
	mut s := validation_session(.spectator)
	assert s.validate_movement(types.Vector3{5000.0, 64.0, 0.0}, 1000)
}

fn test_an_unspawned_session_is_not_checked() {
	mut s := validation_session(.survival)
	s.spawned = false
	assert s.validate_movement(types.Vector3{5000.0, 64.0, 0.0}, 1000)
}

fn test_attack_reach_is_shorter_in_survival() {
	assert attack_reach_sq(.survival) < attack_reach_sq(.creative)
	assert attack_reach_sq(.adventure) == attack_reach_sq(.survival)
}
