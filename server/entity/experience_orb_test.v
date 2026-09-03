module entity

fn test_a_small_award_is_one_orb() {
	values := split_experience(4)
	assert values == [4]
}

fn test_a_big_award_is_split_largest_first() {
	values := split_experience(25)
	assert values == [orb_max_value, orb_max_value, 3]
	mut total := 0
	for value in values {
		total += value
	}
	assert total == 25
}

fn test_nothing_splits_into_nothing() {
	assert split_experience(0).len == 0
	assert split_experience(-5).len == 0
}

fn test_an_orb_is_an_xp_orb() {
	orb := new_experience_orb_behaviour(3, orb_pickup_delay_ticks)
	assert orb.identifier() == 'minecraft:xp_orb'
	assert orb.value == 3
	assert !orb.takes_fall_damage()
}
