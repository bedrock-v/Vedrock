module effect

import time

pub const ticks_per_second = 20
const tick_duration = time.second / ticks_per_second

// Category labels whether an effect is helpful, harmful, or neither.
// Used for UI tinting and for colour-blend weighting.
pub enum Category {
	beneficial
	harmful
	neutral
}

pub struct Type {
pub:
	id       int
	name     string
	lasting  bool
	rgb      [3]u8
	category Category = .neutral
}

// colour returns the RGB value packed into an ARGB int (A=0xFF), suitable for
// entity metadata.
pub fn (t Type) colour() int {
	return int(u32(t.rgb[0]) << 16 | u32(t.rgb[1]) << 8 | u32(t.rgb[2]))
}

// blend_colour averages the RGB colours of all lasting effects and returns a single
// packed ARGB int. Returns 0 when effects is empty or none of the effects have
// visible potion particles — the client hides particles when the colour is 0.
// https://minecraft.fandom.com/fr/wiki/Effet#Particules
pub fn blend_colour(effects []Effect) int {
	if effects.len == 0 {
		return 0
	}
	mut r_sum := 0
	mut g_sum := 0
	mut b_sum := 0
	mut count := 0
	for e in effects {
		if !e.effect_type().lasting || e.particles_hidden {
			continue
		}
		r_sum += int(e.typ.rgb[0])
		g_sum += int(e.typ.rgb[1])
		b_sum += int(e.typ.rgb[2])
		count++
	}
	if count == 0 {
		return 0
	}
	r := u8(r_sum / count)
	g := u8(g_sum / count)
	b := u8(b_sum / count)
	// Bedrock EFFECT_COLOR metadata uses 24-bit RGB (no alpha).
	return int(u32(r) << 16 | u32(g) << 8 | u32(b))
}

// any_ambient reports whether any of the active effects has its ambient flag set.
// Drives the entity metadata flag that dims potion particles (beacon style).
pub fn any_ambient(effects []Effect) bool {
	for e in effects {
		if e.ambient {
			return true
		}
	}
	return false
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

// new_with_ticks creates a lasting effect with a duration expressed in ticks
// instead of a time.Duration. Used when scaling durations, e.g. splash potions.
pub fn new_with_ticks(typ Type, level int, ticks int) Effect {
	return Effect{
		typ:            typ
		level:          level
		duration_ticks: ticks
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
