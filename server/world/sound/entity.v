module sound

// Attack is played when an entity is hit. A hit that deals no damage, such as
// one fully absorbed by a shield, uses a quieter sound.
pub struct Attack {
pub:
	damage bool
}

pub fn (s Attack) event_name() string {
	return if s.damage { 'attack.strong' } else { 'attack.nodamage' }
}

pub fn (s Attack) data() i32 {
	return no_data
}

// Fall is played when an entity hits the ground. A fall from a bigger height
// is louder.
pub struct Fall {
pub:
	distance f64
}

pub fn (s Fall) event_name() string {
	return if s.distance > 7.0 { 'fall.big' } else { 'fall.small' }
}

pub fn (s Fall) data() i32 {
	return no_data
}

// Burning is played while an entity is on fire.
pub struct Burning {}

pub fn (s Burning) event_name() string {
	return 'player.hurt_on_fire'
}

pub fn (s Burning) data() i32 {
	return no_data
}

// Drowning is played while an entity runs out of air underwater.
pub struct Drowning {}

pub fn (s Drowning) event_name() string {
	return 'player.hurt_drown'
}

pub fn (s Drowning) data() i32 {
	return no_data
}

// Burp is played when a player finishes eating.
pub struct Burp {}

pub fn (s Burp) event_name() string {
	return 'burp'
}

pub fn (s Burp) data() i32 {
	return no_data
}

// Pop is played when an item is picked up.
pub struct Pop {}

pub fn (s Pop) event_name() string {
	return 'pop'
}

pub fn (s Pop) data() i32 {
	return no_data
}

// Explosion is played when something explodes.
pub struct Explosion {}

pub fn (s Explosion) event_name() string {
	return 'explode'
}

pub fn (s Explosion) data() i32 {
	return no_data
}

// Thunder is played when lightning strikes.
pub struct Thunder {}

pub fn (s Thunder) event_name() string {
	return 'thunder'
}

pub fn (s Thunder) data() i32 {
	return no_data
}

// LevelUp is played when a player gains an experience level.
pub struct LevelUp {}

pub fn (s LevelUp) event_name() string {
	return 'levelup'
}

pub fn (s LevelUp) data() i32 {
	return no_data
}

// Experience is played when a player picks up an experience orb.
pub struct Experience {}

pub fn (s Experience) event_name() string {
	return 'experience_orb.pickup'
}

pub fn (s Experience) data() i32 {
	return no_data
}
