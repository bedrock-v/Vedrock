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

pub const speed = Type{
	id:      1
	name:    'speed'
	lasting: true
}
pub const slowness = Type{
	id:      2
	name:    'slowness'
	lasting: true
}
pub const haste = Type{
	id:      3
	name:    'haste'
	lasting: true
}
pub const mining_fatigue = Type{
	id:      4
	name:    'mining_fatigue'
	lasting: true
}
pub const strength = Type{
	id:      5
	name:    'strength'
	lasting: true
}
pub const instant_health = Type{
	id:   6
	name: 'instant_health'
}
pub const instant_damage = Type{
	id:   7
	name: 'instant_damage'
}
pub const jump_boost = Type{
	id:      8
	name:    'jump_boost'
	lasting: true
}
pub const nausea = Type{
	id:      9
	name:    'nausea'
	lasting: true
}
pub const regeneration = Type{
	id:      10
	name:    'regeneration'
	lasting: true
}
pub const resistance = Type{
	id:      11
	name:    'resistance'
	lasting: true
}
pub const fire_resistance = Type{
	id:      12
	name:    'fire_resistance'
	lasting: true
}
pub const water_breathing = Type{
	id:      13
	name:    'water_breathing'
	lasting: true
}
pub const invisibility = Type{
	id:      14
	name:    'invisibility'
	lasting: true
}
pub const blindness = Type{
	id:      15
	name:    'blindness'
	lasting: true
}
pub const night_vision = Type{
	id:      16
	name:    'night_vision'
	lasting: true
}
pub const hunger = Type{
	id:      17
	name:    'hunger'
	lasting: true
}
pub const weakness = Type{
	id:      18
	name:    'weakness'
	lasting: true
}
pub const poison = Type{
	id:      19
	name:    'poison'
	lasting: true
}
pub const wither = Type{
	id:      20
	name:    'wither'
	lasting: true
}
pub const health_boost = Type{
	id:      21
	name:    'health_boost'
	lasting: true
}
pub const absorption = Type{
	id:      22
	name:    'absorption'
	lasting: true
}
pub const saturation = Type{
	id:   23
	name: 'saturation'
}
pub const levitation = Type{
	id:      24
	name:    'levitation'
	lasting: true
}
pub const fatal_poison = Type{
	id:      25
	name:    'fatal_poison'
	lasting: true
}
pub const conduit_power = Type{
	id:      26
	name:    'conduit_power'
	lasting: true
}
pub const slow_falling = Type{
	id:      27
	name:    'slow_falling'
	lasting: true
}
pub const darkness = Type{
	id:      30
	name:    'darkness'
	lasting: true
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
