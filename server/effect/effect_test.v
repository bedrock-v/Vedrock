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

fn test_type_colour_packs_argb() {
	assert speed.colour() == 0x0033ebff
	assert instant_health.colour() == 0x00f82423
	assert darkness.colour() == 0x00292721
}

fn test_blend_colour_averages_rgb() {
	// RGBs: speed (0x33,0xeb,0xff), slowness (0x8b,0xaf,0xe0)
	// avg: ((51+139)/2, (235+175)/2, (255+224)/2) = (95, 205, 239) = 0x5FCDEF
	e1 := new(speed, 1, 1 * time.second)
	e2 := new(slowness, 1, 1 * time.second)
	c := blend_colour([e1, e2])
	assert c == 0x005fcdef
}

fn test_blend_colour_empty_returns_zero() {
	assert blend_colour([]Effect{}) == 0
}

fn test_blend_colour_skips_non_lasting() {
	// Only instant effects - should return 0 since particles don't persist.
	e := new_instant(instant_health, 1)
	assert blend_colour([e]) == 0
}

fn test_blend_colour_skips_hidden_particles() {
	mut e := new(speed, 1, 1 * time.second)
	ep := e.without_particles()
	// Only hidden-particles effects: colour should be 0.
	assert blend_colour([ep]) == 0
	// Mix of visible and hidden: visible wins.
	c := blend_colour([e, ep])
	assert c == speed.colour()
}

fn test_any_ambient_detects_ambient_flag() {
	assert !any_ambient([]Effect{})
	e := new(speed, 1, 1 * time.second)
	assert !any_ambient([e])
	ea := new_ambient(speed, 1, 1 * time.second)
	assert any_ambient([ea])
}

fn test_type_has_rgb_and_category() {
	assert speed.rgb[0] == u8(0x33)
	assert speed.rgb[1] == u8(0xeb)
	assert speed.rgb[2] == u8(0xff)
	assert speed.category == .beneficial
	assert slowness.category == .harmful
	assert instant_health.category == .beneficial
	assert instant_damage.category == .harmful
	assert wither.category == .harmful
	assert regeneration.category == .beneficial
}
