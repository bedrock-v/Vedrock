module title

import time

fn test_new_title_uses_the_default_durations() {
	t := new('Welcome')
	assert t.text() == 'Welcome'
	assert t.subtitle() == ''
	assert t.action_text() == ''
	assert t.fade_in_duration() == tick
	assert t.fade_out_duration() == tick
	assert t.duration() == 2 * time.second
}

fn test_with_methods_leave_the_original_untouched() {
	t := new('Welcome')
	changed :=
		t.with_subtitle('to the server').with_action_text('hi').with_duration(5 * time.second)
	assert changed.subtitle() == 'to the server'
	assert changed.action_text() == 'hi'
	assert changed.duration() == 5 * time.second
	assert t.subtitle() == ''
	assert t.duration() == 2 * time.second
}

fn test_ticks_rounds_down_and_never_goes_negative() {
	assert ticks(2 * time.second) == 40
	assert ticks(tick / 2) == 0
	assert ticks(-time.second) == 0
}
