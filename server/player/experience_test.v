module player

fn test_the_curve_steepens_twice() {
	assert experience_to_next_level(0) == 7
	assert experience_to_next_level(15) == 37
	assert experience_to_next_level(16) == 42
	assert experience_to_next_level(30) == 112
	assert experience_to_next_level(31) == 121
}

fn test_a_fresh_player_has_nothing() {
	p := new_player()
	state := p.experience()
	assert state.level == 0
	assert state.progress == 0
}

fn test_points_fill_the_bar_before_the_level() {
	mut p := new_player()
	p.add_experience(3)
	state := p.experience()
	assert state.level == 0
	// Three of the seven points the first level costs.
	assert state.progress > 0.42 && state.progress < 0.43
}

fn test_enough_points_level_the_player_up() {
	mut p := new_player()
	// The first two levels cost 7 and 9, so 17 points is level 2 with 1 over.
	p.add_experience(17)
	state := p.experience()
	assert state.level == 2
	assert state.progress > 0.09 && state.progress < 0.1
}

fn test_negative_points_take_levels_back() {
	mut p := new_player()
	p.add_experience(17)
	p.add_experience(-10)
	state := p.experience()
	// 7 points left is exactly the first level and nothing into the second.
	assert state.level == 1
	assert state.progress == 0
}

fn test_experience_never_goes_below_nothing() {
	mut p := new_player()
	p.add_experience(5)
	p.add_experience(-1000)
	state := p.experience()
	assert state.level == 0
	assert state.progress == 0
}

fn test_levels_move_whole_steps() {
	mut p := new_player()
	p.add_experience_levels(5)
	assert p.experience_level() == 5
	p.add_experience_levels(-2)
	assert p.experience_level() == 3
	p.add_experience_levels(-100)
	assert p.experience_level() == 0
}

fn test_death_drops_seven_a_level_up_to_the_cap() {
	mut p := new_player()
	p.set_experience(ExperienceState{
		level: 3
	})
	assert p.dropped_experience() == 21
	p.set_experience(ExperienceState{
		level: 50
	})
	assert p.dropped_experience() == experience_death_cap
}

fn test_reset_empties_the_bar() {
	mut p := new_player()
	p.add_experience(100)
	p.reset_experience()
	state := p.experience()
	assert state.level == 0
	assert state.progress == 0
}
