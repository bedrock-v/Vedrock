module effect

import time

fn test_effect_duration_ticks() {
	e := new(regeneration, 2, 5 * time.second)
	assert e.level() == 2
	assert e.duration_ticks() == 100
	assert e.duration() == 5 * time.second
}

fn test_manager_keeps_stronger_or_longer_effect() {
	mut m := new_manager()
	short := new(speed, 1, 5 * time.second)
	long := new(speed, 1, 10 * time.second)
	strong := new(speed, 2, 2 * time.second)

	assert m.add(short).duration_ticks() == 100
	assert m.add(long).duration_ticks() == 200
	assert m.add(short).duration_ticks() == 200
	assert m.add(strong).level() == 2
	assert (m.effect(speed) or { panic('missing speed') }).level() == 2
}

fn test_manager_reports_rejected_weaker_effect() {
	mut m := new_manager()
	m.add(new(speed, 2, 5 * time.second))
	result := m.add_result(new(speed, 1, 10 * time.second))

	assert !result.accepted
	assert result.stored
	assert result.effect.level() == 2
	assert result.effect.duration_ticks() == 100
}

fn test_manager_ticks_and_expires() {
	mut m := new_manager()
	m.add(new(poison, 1, 50 * time.millisecond))
	first := m.tick()
	assert first.active.len == 1
	assert first.expired.len == 0
	second := m.tick()
	assert second.active.len == 0
	assert second.expired.len == 1
	if _ := m.effect(poison) {
		assert false
	}
}

fn test_instant_effect_is_not_stored() {
	mut m := new_manager()
	e := m.add(new_instant(instant_health, 1))
	assert e.instant()
	assert m.effects().len == 0
}
