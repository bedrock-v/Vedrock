module player

fn test_a_fresh_player_starts_fed() {
	p := new_player()
	state := p.hunger()
	assert state.food_level == max_food_level
	assert state.saturation == initial_saturation
	assert state.exhaustion == 0
}

fn test_exhaustion_below_the_threshold_moves_nothing_visible() {
	mut p := new_player()
	assert !p.exhaust(3.9)
	state := p.hunger()
	assert state.food_level == max_food_level
	assert state.saturation == initial_saturation
	assert state.exhaustion > 3.89 && state.exhaustion < 3.91
}

fn test_saturation_is_spent_before_food() {
	mut p := new_player()
	assert p.exhaust(exhaustion_threshold)
	state := p.hunger()
	assert state.food_level == max_food_level
	assert state.saturation == initial_saturation - 1.0
	assert state.exhaustion == 0
}

fn test_food_is_spent_once_saturation_runs_out() {
	mut p := new_player()
	// Five points of saturation, then the sixth unit comes off the bar.
	p.exhaust(exhaustion_threshold * 6)
	state := p.hunger()
	assert state.saturation == 0
	assert state.food_level == max_food_level - 1
}

fn test_an_empty_bar_does_not_bank_exhaustion() {
	mut p := new_player()
	p.set_hunger(HungerState{})
	p.exhaust(exhaustion_threshold * 10)
	state := p.hunger()
	assert state.food_level == 0
	assert state.exhaustion == 0
}

fn test_eating_restores_food_and_saturation() {
	mut p := new_player()
	p.set_hunger(HungerState{
		food_level: 10
	})
	// Bread: 5 nutrition at a 0.6 modifier, so 6 saturation behind it.
	p.eat(5, 0.6)
	state := p.hunger()
	assert state.food_level == 15
	assert state.saturation > 5.99 && state.saturation < 6.01
}

fn test_saturation_cannot_exceed_the_food_it_sits_behind() {
	mut p := new_player()
	p.set_hunger(HungerState{
		food_level: 4
	})
	p.eat(2, 4.0)
	state := p.hunger()
	assert state.food_level == 6
	assert state.saturation == 6.0
}

fn test_eating_never_overfills_the_bar() {
	mut p := new_player()
	p.eat(10, 1.0)
	state := p.hunger()
	assert state.food_level == max_food_level
	assert state.saturation == f32(max_food_level)
}

fn test_reset_hunger_returns_a_spawning_bar() {
	mut p := new_player()
	p.set_hunger(HungerState{
		food_level: 2
		saturation: 0
		exhaustion: 3
	})
	p.reset_hunger()
	state := p.hunger()
	assert state.food_level == max_food_level
	assert state.saturation == initial_saturation
	assert state.exhaustion == 0
}

fn test_hunger_position_starts_unsampled() {
	mut p := new_player()
	if _ := p.hunger_position() {
		assert false, 'a player who has not moved yet reported a sample'
	}
	p.set_hunger_position(p.position())
	if _ := p.hunger_position() {
	} else {
		assert false, 'sample was not recorded'
	}
}
