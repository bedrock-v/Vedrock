module session

import math
import bedrock_v.protocol.current as proto
import server.item
import server.player
import server.worldrt

// food_regeneration_threshold is the food level a player has to be at or above
// before health comes back on its own.
const food_regeneration_threshold = 18

// regeneration_interval_ticks and starvation_interval_ticks pace the two
// opposite ends of the bar: one heal, or one point of starvation damage, per
// interval.
const regeneration_interval_ticks = i64(80)
const starvation_interval_ticks = i64(80)

// peaceful_feed_interval_ticks is how often the bar refills itself when there
// is no difficulty to go hungry under.
const peaceful_feed_interval_ticks = i64(20)

const starvation_damage = f32(1.0)

// max_player_health is a full health bar, the ceiling regeneration heals to.
const max_player_health = f32(20.0)

// starvation_floor is the health starvation stops at, by difficulty: peaceful
// never starves at all, easy leaves half a bar, normal a single point, and
// hard takes the player all the way down.
fn starvation_floor(difficulty int) f32 {
	return match difficulty {
		proto.difficulty_easy { 10.0 }
		proto.difficulty_normal { 1.0 }
		else { 0.0 }
	}
}

// tick_hunger advances one player's hunger bar for the owning world's
// simulation step: what their movement cost them, then whatever the resulting
// food level does to their health.
fn (mut s NetworkSession) tick_hunger(mut tx worldrt.WorldTx) {
	if s.player.is_dead() || !s.hunger_applies() {
		return
	}
	tick := s.player.advance_hunger_clock()
	difficulty := s.hub.difficulty_value()
	if difficulty == proto.difficulty_peaceful {
		s.tick_peaceful_hunger(tick)
		return
	}
	mut changed := s.exhaust_movement()
	state := s.player.hunger()
	if state.food_level >= food_regeneration_threshold {
		if s.regenerate(tick) {
			changed = true
		}
	} else if state.food_level == 0 {
		s.starve(mut tx, tick, difficulty)
	}
	if changed {
		s.send_hunger()
	}
}

// hunger_applies reports whether the player is in a mode that gets hungry at
// all. Creative and spectator neither lose food nor starve.
fn (s &NetworkSession) hunger_applies() bool {
	return s.player.game_mode().allows_taking_damage()
}

// tick_peaceful_hunger refills the bar instead of draining it.
fn (mut s NetworkSession) tick_peaceful_hunger(tick i64) {
	// Sample the position anyway, or the first tick back on a harder
	// difficulty would charge for every metre walked while on peaceful.
	s.player.set_hunger_position(s.current_position())
	if tick % peaceful_feed_interval_ticks != 0 {
		return
	}
	if s.player.food_level() >= player.max_food_level {
		return
	}
	s.player.feed(1)
	s.send_hunger()
}

// exhaust_movement charges the player for the ground they covered since the
// last step. Walking is free, so only sprinting and swimming are billed.
fn (mut s NetworkSession) exhaust_movement() bool {
	pos := s.current_position()
	previous := s.player.hunger_position() or {
		s.player.set_hunger_position(pos)
		return false
	}
	s.player.set_hunger_position(pos)
	rate := if s.player.sprinting() {
		player.sprint_exhaustion_per_metre
	} else if s.player.swimming() {
		player.swim_exhaustion_per_metre
	} else {
		return false
	}
	dx := pos.x - previous.x
	dz := pos.z - previous.z
	distance := math.sqrtf(dx * dx + dz * dz)
	if distance <= 0 {
		return false
	}
	return s.player.exhaust(rate * distance)
}

// regenerate heals a point off a well fed player and charges them for it.
fn (mut s NetworkSession) regenerate(tick i64) bool {
	if tick % regeneration_interval_ticks != 0 {
		return false
	}
	health := s.player.health()
	if health >= max_player_health {
		return false
	}
	s.player.set_health(math.min(max_player_health, health + 1.0))
	s.deliver(s.health_update())
	return s.player.exhaust(player.regeneration_exhaustion)
}

// starve applies the damage an empty bar deals, down to the floor the current
// difficulty allows.
fn (mut s NetworkSession) starve(mut tx worldrt.WorldTx, tick i64, difficulty int) {
	if tick % starvation_interval_ticks != 0 {
		return
	}
	if s.player.health() - starvation_damage < starvation_floor(difficulty) {
		return
	}
	s.apply_hurt(mut tx, starvation_damage, StarvationDamageSource{})
}

// exhaust_and_sync spends exhaustion from somewhere other than the hunger tick
// - a swing of a pickaxe, a hit taken - and resends the bar if it moved.
fn (mut s NetworkSession) exhaust_and_sync(amount f32) {
	if !s.hunger_applies() {
		return
	}
	if s.player.exhaust(amount) {
		s.send_hunger()
	}
}

// eat_result applies what a consumed item restores. Items with no nutrition
// (a potion, a milk bucket) leave the bar alone.
fn (mut s NetworkSession) eat_item(name string) {
	it := item.get(name) or { return }
	if it.nutrition() <= 0 {
		return
	}
	s.player.eat(it.nutrition(), it.saturation())
	s.send_hunger()
}

fn (mut s NetworkSession) send_hunger() {
	if !s.spawned {
		return
	}
	s.deliver(s.player.hunger_update())
}

// jump_exhaustion_for is what leaving the ground costs, which sprinting makes
// four times more expensive.
fn jump_exhaustion_for(sprinting bool) f32 {
	return if sprinting { player.sprint_jump_exhaustion } else { player.jump_exhaustion }
}

// apply_input_state records the movement state the client reports, so the
// hunger tick knows what the metres it sees were covered by.
fn (mut s NetworkSession) apply_input_state(input_data []proto.PlayerAuthInputData) {
	sprinting := proto.PlayerAuthInputData.sprinting in input_data
	s.player.set_sprinting(sprinting)
	if proto.PlayerAuthInputData.start_swimming in input_data {
		s.player.set_swimming(true)
	} else if proto.PlayerAuthInputData.stop_swimming in input_data {
		s.player.set_swimming(false)
	}
	if proto.PlayerAuthInputData.start_jumping in input_data {
		s.exhaust_and_sync(jump_exhaustion_for(sprinting))
	}
}
