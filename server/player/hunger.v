module player

import math
import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import server.player.playerdb

// max_food_level is a full hunger bar, and initial_saturation is what a fresh
// or respawned player starts with behind it. Both come from the save format,
// which has to know them to default a save that predates hunger.
pub const max_food_level = playerdb.max_food_level
pub const initial_saturation = playerdb.initial_saturation

// exhaustion_threshold is how much exhaustion one point of saturation - or,
// with none left, one point of food - is worth.
pub const exhaustion_threshold = f32(4.0)

// Movement costs are per metre travelled. Walking is free; only the faster
// ways of getting somewhere are paid for.
pub const sprint_exhaustion_per_metre = f32(0.1)
pub const swim_exhaustion_per_metre = f32(0.01)

pub const jump_exhaustion = f32(0.05)
pub const sprint_jump_exhaustion = f32(0.2)
pub const mining_exhaustion = f32(0.005)
pub const damage_exhaustion = f32(0.1)
pub const regeneration_exhaustion = f32(6.0)

// regeneration_interval_ticks and starvation_interval_ticks are how many
// consecutive ticks a player has to spend eligible before a point of health
// moves, and passive_feed_interval_ticks how often peaceful refills the bar.
pub const regeneration_interval_ticks = 80
pub const starvation_interval_ticks = 80
pub const passive_feed_interval_ticks = 20

// HungerState is a snapshot of the whole bar, for the callers that need to
// read it as one consistent set rather than field by field.
pub struct HungerState {
pub:
	food_level int
	saturation f32
	exhaustion f32
}

pub fn (p &Player) hunger() HungerState {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return HungerState{
		food_level: p.food_level
		saturation: p.saturation
		exhaustion: p.exhaustion
	}
}

pub fn (p &Player) food_level() int {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.food_level
}

pub fn (mut p Player) set_hunger(state HungerState) {
	p.state_mutex.lock()
	p.food_level = clamp_food(state.food_level)
	p.saturation = clamp_saturation(state.saturation, p.food_level)
	p.exhaustion = math.max(f32(0), state.exhaustion)
	p.state_mutex.unlock()
}

// reset_hunger puts the bar back to what a player spawns with.
pub fn (mut p Player) reset_hunger() {
	p.set_hunger(HungerState{
		food_level: max_food_level
		saturation: initial_saturation
	})
}

// advance_regeneration counts one tick spent well fed enough to heal, and
// reports whether that was the tick a point of health comes back on.
//
// The counter only runs while the condition holds and resets the moment it
// stops, so a player who has just eaten waits the full interval rather than
// inheriting wherever a shared clock happened to be.
pub fn (mut p Player) advance_regeneration(eligible bool) bool {
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	if !eligible {
		p.regeneration_ticks = 0
		return false
	}
	p.regeneration_ticks++
	if p.regeneration_ticks < regeneration_interval_ticks {
		return false
	}
	p.regeneration_ticks = 0
	return true
}

// advance_starvation is the same counter for an empty bar.
pub fn (mut p Player) advance_starvation(eligible bool) bool {
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	if !eligible {
		p.starvation_ticks = 0
		return false
	}
	p.starvation_ticks++
	if p.starvation_ticks < starvation_interval_ticks {
		return false
	}
	p.starvation_ticks = 0
	return true
}

// advance_passive_feed paces the refill on peaceful the same way.
pub fn (mut p Player) advance_passive_feed() bool {
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	p.passive_feed_ticks++
	if p.passive_feed_ticks < passive_feed_interval_ticks {
		return false
	}
	p.passive_feed_ticks = 0
	return true
}

// charge_movement bills the ground covered since the last sample at the rate
// the player is moving at now, and reports whether the visible bar moved.
//
// Every caller that changes how movement is paid for settles the outstanding
// distance through here first, so a segment is always charged at the rate that
// was actually true while it was being travelled. Sprinting for ten metres and
// then stopping costs the sprint rate for those ten metres, not the walking
// one, and starting to sprint does not retroactively bill the walk before it.
pub fn (mut p Player) charge_movement(pos types.Vector3) bool {
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	previous := p.hunger_position
	had_sample := p.has_hunger_position
	p.hunger_position = pos
	p.has_hunger_position = true
	if !had_sample {
		return false
	}
	rate := p.movement_exhaustion_rate()
	if rate <= 0 {
		return false
	}
	dx := pos.x - previous.x
	dz := pos.z - previous.z
	distance := math.sqrtf(dx * dx + dz * dz)
	if distance <= 0 {
		return false
	}
	return p.spend_exhaustion(rate * distance)
}

// movement_exhaustion_rate is what a metre costs in the player's current
// state. The caller must already hold state_mutex.
fn (p &Player) movement_exhaustion_rate() f32 {
	if p.sprinting {
		return sprint_exhaustion_per_metre
	}
	if p.swimming {
		return swim_exhaustion_per_metre
	}
	return 0
}

// hunger_position is where the player was when their movement was last
// charged for, or none before the first sample.
pub fn (p &Player) hunger_position() ?types.Vector3 {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	if !p.has_hunger_position {
		return none
	}
	return p.hunger_position
}

pub fn (mut p Player) set_hunger_position(pos types.Vector3) {
	p.state_mutex.lock()
	p.hunger_position = pos
	p.has_hunger_position = true
	p.state_mutex.unlock()
}

pub fn (p &Player) sprinting() bool {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.sprinting
}

// set_sprinting settles what has been travelled so far before the rate
// changes, so the distance already covered is billed at the old rate.
pub fn (mut p Player) set_sprinting(pos types.Vector3, value bool) bool {
	if p.sprinting() == value {
		return false
	}
	changed := p.charge_movement(pos)
	p.state_mutex.lock()
	p.sprinting = value
	p.state_mutex.unlock()
	return changed
}

pub fn (p &Player) swimming() bool {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.swimming
}

// set_swimming settles the outstanding distance the same way set_sprinting
// does.
pub fn (mut p Player) set_swimming(pos types.Vector3, value bool) bool {
	if p.swimming() == value {
		return false
	}
	changed := p.charge_movement(pos)
	p.state_mutex.lock()
	p.swimming = value
	p.state_mutex.unlock()
	return changed
}

// exhaust adds amount to the exhaustion counter and spends whatever whole
// units of it that buys, saturation first and food after. It reports whether
// the visible part of the bar moved, so a caller only resends what changed.
pub fn (mut p Player) exhaust(amount f32) bool {
	if amount <= 0 {
		return false
	}
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	return p.spend_exhaustion(amount)
}

// spend_exhaustion is exhaust's body, for the callers that already hold
// state_mutex.
fn (mut p Player) spend_exhaustion(amount f32) bool {
	if amount <= 0 {
		return false
	}
	before_food := p.food_level
	before_saturation := p.saturation
	p.exhaustion += amount
	for p.exhaustion >= exhaustion_threshold {
		p.exhaustion -= exhaustion_threshold
		if p.saturation > 0 {
			p.saturation = math.max(f32(0), p.saturation - 1.0)
		} else if p.food_level > 0 {
			p.food_level--
		} else {
			// Nothing left to spend it on. Dropping the surplus keeps a
			// starving player from banking exhaustion against their next meal.
			p.exhaustion = 0
			break
		}
	}
	return p.food_level != before_food || p.saturation != before_saturation
}

// eat restores food and saturation the way a food item does: saturation is
// capped by the food level it is carried by, so a full bar cannot bank more of
// it than it has room for.
pub fn (mut p Player) eat(nutrition int, saturation_modifier f32) {
	p.state_mutex.lock()
	p.food_level = clamp_food(p.food_level + nutrition)
	gained := f32(nutrition) * saturation_modifier * 2.0
	p.saturation = clamp_saturation(p.saturation + gained, p.food_level)
	p.state_mutex.unlock()
}

// feed adds food levels without any saturation behind them, as passive
// difficulty's slow refill does.
pub fn (mut p Player) feed(points int) {
	p.state_mutex.lock()
	p.food_level = clamp_food(p.food_level + points)
	p.state_mutex.unlock()
}

fn clamp_food(value int) int {
	if value < 0 {
		return 0
	}
	if value > max_food_level {
		return max_food_level
	}
	return value
}

fn clamp_saturation(value f32, food_level int) f32 {
	return math.min(math.max(f32(0), value), f32(food_level))
}

// hunger_update is the hunger bar alone, for the common case where nothing
// else about the player changed.
pub fn (p &Player) hunger_update() &proto.UpdateAttributesPacket {
	state := p.hunger()
	mut sink := p.sink
	return &proto.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(sink.runtime_id())
		attribute_list:          [
			player_attribute('minecraft:player.hunger', 0.0, f32(max_food_level),
				f32(state.food_level)),
			player_attribute('minecraft:player.saturation', 0.0, f32(max_food_level),
				state.saturation),
			player_attribute('minecraft:player.exhaustion', 0.0, exhaustion_threshold,
				state.exhaustion),
		]
		ticks_since_sim_started: 0
	}
}
