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
	mut s := &NetworkSession{
		player: pl
	}
	s.player.set_game_mode(.survival)
	s.player.reset_position(vector_at(0))
	// The first step only records where the player is.
	assert !s.exhaust_movement()
	s.player.reset_position(vector_at(100))
	assert !s.exhaust_movement()
	assert s.player.hunger().exhaustion == 0

	s.player.set_sprinting(true)
	s.player.reset_position(vector_at(200))
	s.exhaust_movement()
	// 100 metres sprinted is 10 exhaustion, which is two whole units spent and
	// a remainder left over.
	state := s.player.hunger()
	assert state.saturation == player.initial_saturation - 2.0
	assert state.exhaustion > 1.99 && state.exhaustion < 2.01
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
