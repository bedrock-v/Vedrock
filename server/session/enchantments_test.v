module session

fn test_efficiency_adds_level_squared_plus_one() {
	assert efficiency_bonus(0) == 0
	assert efficiency_bonus(1) == 2
	assert efficiency_bonus(3) == 10
	assert efficiency_bonus(5) == 26
}

fn test_unbreaking_only_ever_skips_damage() {
	// Without the enchantment every point of damage lands.
	for _ in 0 .. 100 {
		assert !survives_unbreaking(0)
	}
	// With it, some do not - over this many rolls at level 3 a run of all
	// hits would be a one in four billion coincidence.
	mut skipped := 0
	for _ in 0 .. 200 {
		if survives_unbreaking(3) {
			skipped++
		}
	}
	assert skipped > 0
	assert skipped < 200
}

fn test_fortune_never_reduces_a_drop() {
	for _ in 0 .. 100 {
		count := fortune_count(1, 3)
		assert count >= 1
		assert count <= 4
	}
	assert fortune_count(2, 0) == 2
	assert fortune_count(0, 3) == 0
}
