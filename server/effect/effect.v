module effect

import time

pub const ticks_per_second = 20
const tick_duration = time.second / ticks_per_second

pub struct Type {
pub:
	id      int
	name    string
	lasting bool
}

pub struct Effect {
mut:
	typ              Type
	level            int
	duration_ticks   int
	potency          f64 = 1.0
	ambient          bool
	particles_hidden bool
	infinite         bool
	instant          bool
	tick             int
}

pub fn new(typ Type, level int, duration time.Duration) Effect {
	return Effect{
		typ:            typ
		level:          level
		duration_ticks: duration_to_ticks(duration)
	}
}

pub fn new_ambient(typ Type, level int, duration time.Duration) Effect {
	mut e := new(typ, level, duration)
	e.ambient = true
	return e
}

pub fn new_infinite(typ Type, level int) Effect {
	return Effect{
		typ:      typ
		level:    level
		infinite: true
	}
}

pub fn new_instant(typ Type, level int) Effect {
	return new_instant_with_potency(typ, level, 1.0)
}

pub fn new_instant_with_potency(typ Type, level int, potency f64) Effect {
	return Effect{
		typ:     typ
		level:   level
		potency: potency
		instant: true
	}
}

pub fn (e Effect) without_particles() Effect {
	mut out := e
	out.particles_hidden = true
	return out
}

pub fn (e Effect) effect_type() Type {
	return e.typ
}

pub fn (e Effect) level() int {
	return e.level
}

pub fn (e Effect) duration() time.Duration {
	return time.Duration(e.duration_ticks) * tick_duration
}

pub fn (e Effect) duration_ticks() int {
	if e.infinite {
		return -1
	}
	return e.duration_ticks
}

pub fn (e Effect) potency() f64 {
	return e.potency
}

pub fn (e Effect) ambient() bool {
	return e.ambient
}

pub fn (e Effect) particles_hidden() bool {
	return e.particles_hidden
}

pub fn (e Effect) infinite() bool {
	return e.infinite
}

pub fn (e Effect) instant() bool {
	return e.instant
}

pub fn (e Effect) tick() int {
	return e.tick
}

fn (e Effect) expired() bool {
	return !e.instant && !e.infinite && e.duration_ticks <= 0
}

fn (e Effect) tick_duration() Effect {
	if e.instant || !e.typ.lasting {
		return e
	}
	mut out := e
	if !out.infinite {
		out.duration_ticks--
	}
	out.tick++
	return out
}

fn duration_to_ticks(duration time.Duration) int {
	if duration <= 0 {
		return 0
	}
	mut ticks := int(duration / tick_duration)
	if ticks < 1 {
		ticks = 1
	}
	return ticks
}
