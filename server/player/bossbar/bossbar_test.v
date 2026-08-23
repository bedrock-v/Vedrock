module bossbar

fn test_new_bar_is_full_and_purple() {
	bar := new('Boss')
	assert bar.text() == 'Boss'
	assert bar.health_percentage() == 1.0
	assert bar.colour() == Colour.purple
}

fn test_with_methods_leave_the_original_untouched() {
	bar := new('Boss')
	changed := bar.with_health_percentage(0.5).with_colour(.red)
	assert changed.health_percentage() == 0.5
	assert changed.colour() == Colour.red
	assert bar.health_percentage() == 1.0
	assert bar.colour() == Colour.purple
}

fn test_health_percentage_is_clamped() {
	assert new('Boss').with_health_percentage(-1.0).health_percentage() == 0.0
	assert new('Boss').with_health_percentage(2.0).health_percentage() == 1.0
}
