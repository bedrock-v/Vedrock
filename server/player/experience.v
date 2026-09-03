module player

import math
import rand
import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import server.entity
import server.worldrt

// max_experience_level is the ceiling the client's level attribute is bounded
// by. It is the vanilla value the attribute has always been sent with.
pub const max_experience_level = f32(24791.0)

// experience_death_cap is the most experience a player drops when they die,
// however much they were carrying.
pub const experience_death_cap = 100

// experience_dropped_per_level is how much of a level is left on the ground
// per level the player had.
pub const experience_dropped_per_level = 7

// ExperienceState is a player's progress: the level they have reached and how
// far into the next one they are, as a fraction the client draws directly.
pub struct ExperienceState {
pub:
	level    int
	progress f32
}

// experience_to_next_level is how many points the given level costs to leave.
// The curve steepens twice, at 16 and at 31.
pub fn experience_to_next_level(level int) int {
	if level >= 31 {
		return 9 * level - 158
	}
	if level >= 16 {
		return 5 * level - 38
	}
	return 2 * level + 7
}

pub fn (p &Player) experience() ExperienceState {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return ExperienceState{
		level:    p.experience_level
		progress: p.experience_progress
	}
}

pub fn (mut p Player) set_experience(state ExperienceState) {
	p.state_mutex.lock()
	p.experience_level = math.max(0, state.level)
	p.experience_progress = math.min(f32(1.0), math.max(f32(0), state.progress))
	p.state_mutex.unlock()
}

// add_experience awards points and carries the player through as many levels
// as they buy. Negative points take levels back the same way.
pub fn (mut p Player) add_experience(points int) {
	if points == 0 {
		return
	}
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	mut total := p.banked_experience() + points
	if total < 0 {
		total = 0
	}
	mut level := 0
	for {
		cost := experience_to_next_level(level)
		if total < cost {
			break
		}
		total -= cost
		level++
	}
	p.experience_level = level
	p.experience_progress = f32(total) / f32(experience_to_next_level(level))
}

// add_experience_levels moves the player whole levels at a time, as an
// enchantment cost or a command does, leaving the progress bar where it is.
pub fn (mut p Player) add_experience_levels(levels int) {
	p.state_mutex.lock()
	p.experience_level = math.max(0, p.experience_level + levels)
	if p.experience_level == 0 && levels < 0 {
		p.experience_progress = 0
	}
	p.state_mutex.unlock()
}

// reset_experience empties the bar, as dying does.
pub fn (mut p Player) reset_experience() {
	p.set_experience(ExperienceState{})
}

// experience_level is the level alone, for the callers that only need it.
pub fn (p &Player) experience_level() int {
	return p.experience().level
}

// dropped_experience is what dying leaves on the ground: seven points per
// level, capped.
pub fn (p &Player) dropped_experience() int {
	return math.min(experience_death_cap, p.experience_level() * experience_dropped_per_level)
}

// banked_experience is the points behind the current level and progress. The
// caller must already hold state_mutex.
fn (p &Player) banked_experience() int {
	mut total := 0
	for level in 0 .. p.experience_level {
		total += experience_to_next_level(level)
	}
	return total + int(p.experience_progress * f32(experience_to_next_level(p.experience_level)))
}

// experience_update is the experience bar alone, for the common case where
// nothing else about the player changed.
pub fn (p &Player) experience_update() &proto.UpdateAttributesPacket {
	state := p.experience()
	mut sink := p.sink
	return &proto.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(sink.runtime_id())
		attribute_list:          [
			player_attribute('minecraft:player.level', 0.0, max_experience_level, f32(state.level)),
			player_attribute('minecraft:player.experience', 0.0, 1.0, state.progress),
		]
		ticks_since_sim_started: 0
	}
}

// drop_experience leaves the player's experience on the ground where they
// fell and empties their bar. Dying is the only thing that calls it, and it
// takes the transaction because the orbs are the world's.
pub fn (mut p Player) drop_experience(mut tx worldrt.WorldTx) {
	dropped := p.dropped_experience()
	p.reset_experience()
	mut sink := p.sink
	sink.deliver(p.experience_update())
	if dropped <= 0 {
		return
	}
	pos := p.position()
	for value in entity.split_experience(dropped) {
		behaviour := entity.new_experience_orb_behaviour(value, entity.orb_pickup_delay_ticks)
		mut e := tx.wr.entities.spawn(behaviour, pos)
		e.set_velocity(types.Vector3{
			x: (rand.f32() * 0.2) - 0.1
			y: 0.2
			z: (rand.f32() * 0.2) - 0.1
		})
	}
}
