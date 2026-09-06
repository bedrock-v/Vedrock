module session

import bedrock_v.protocol.current as proto
import bedrock_v.protocol.types
import server.player

fn vector_at(x f32) types.Vector3 {
	return types.Vector3{x, 64.0, 0.0}
}

fn test_starvation_floor_by_difficulty() {
	assert starvation_floor(proto.difficulty_easy) == 10.0
	assert starvation_floor(proto.difficulty_normal) == 1.0
	assert starvation_floor(proto.difficulty_hard) == 0.0
}

fn test_sprinting_makes_a_jump_cost_more() {
	assert jump_exhaustion_for(false) == player.jump_exhaustion
	assert jump_exhaustion_for(true) == player.sprint_jump_exhaustion
	assert jump_exhaustion_for(true) > jump_exhaustion_for(false)
}

fn test_only_survival_gets_hungry() {
	mut pl := player.new_player()
	mut s := &NetworkSession{
		player: pl
	}
	s.player.set_game_mode(.survival)
	assert s.hunger_applies()
	s.player.set_game_mode(.creative)
	assert !s.hunger_applies()
	s.player.set_game_mode(.spectator)
	assert !s.hunger_applies()
}

fn test_walking_is_free_but_sprinting_is_not() {
	mut pl := player.new_player()
	// The first sample only records where the player is.
	assert !pl.charge_movement(vector_at(0))
	assert !pl.charge_movement(vector_at(100))
	assert pl.hunger().exhaustion == 0

	pl.set_sprinting(vector_at(100), true)
	pl.charge_movement(vector_at(200))
	// 100 metres sprinted is 10 exhaustion, which is two whole units spent and
	// a remainder left over.
	state := pl.hunger()
	assert state.saturation == player.initial_saturation - 2.0
	assert state.exhaustion > 1.99 && state.exhaustion < 2.01
}

fn test_a_segment_is_billed_at_the_rate_it_was_travelled_at() {
	mut pl := player.new_player()
	pl.charge_movement(vector_at(0))
	// Ten metres walked while the sprint flag is still off.
	pl.set_sprinting(vector_at(10), true)
	assert pl.hunger().exhaustion == 0

	// Ten more sprinted, then the flag drops: only the sprinted stretch is
	// billed, and stopping does not retroactively charge the walk.
	pl.set_sprinting(vector_at(20), false)
	sprinted := pl.hunger().exhaustion
	assert sprinted > 0.99 && sprinted < 1.01

	pl.charge_movement(vector_at(120))
	assert pl.hunger().exhaustion == sprinted
}

fn test_regeneration_waits_a_full_interval_after_becoming_eligible() {
	mut pl := player.new_player()
	// Ineligible ticks never bring the timer closer to firing.
	for _ in 0 .. 500 {
		assert !pl.advance_regeneration(false)
	}
	for _ in 0 .. player.regeneration_interval_ticks - 1 {
		assert !pl.advance_regeneration(true)
	}
	assert pl.advance_regeneration(true)
}

fn test_an_interrupted_condition_starts_the_wait_again() {
	mut pl := player.new_player()
	for _ in 0 .. player.starvation_interval_ticks - 1 {
		pl.advance_starvation(true)
	}
	// One tick spent fed resets it, so the next one does not fire.
	pl.advance_starvation(false)
	assert !pl.advance_starvation(true)
}

fn test_swimming_costs_less_than_sprinting() {
	assert player.swim_exhaustion_per_metre < player.sprint_exhaustion_per_metre
}

fn test_input_state_is_recorded_from_the_client() {
	mut pl := player.new_player()
	mut s := &NetworkSession{
		player: pl
	}
	s.player.set_game_mode(.survival)
	s.apply_input_state([proto.PlayerAuthInputData.sprinting, .start_swimming])
	assert s.player.sprinting()
	assert s.player.swimming()

	s.apply_input_state([proto.PlayerAuthInputData.stop_swimming])
	assert !s.player.sprinting()
	assert !s.player.swimming()
}

fn test_jumping_spends_exhaustion() {
	mut pl := player.new_player()
	mut s := &NetworkSession{
		player: pl
	}
	s.player.set_game_mode(.survival)
	s.apply_input_state([proto.PlayerAuthInputData.start_jumping])
	assert s.player.hunger().exhaustion == player.jump_exhaustion

	s.player.set_game_mode(.creative)
	s.apply_input_state([proto.PlayerAuthInputData.start_jumping])
	assert s.player.hunger().exhaustion == player.jump_exhaustion
}
