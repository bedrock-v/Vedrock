module session

import math
import time
import bedrock_v.protocol.types
import server.effect
import server.player

// Movement budgets are per simulated tick and deliberately generous: they are
// there to catch a client claiming to be somewhere it cannot have walked to,
// not to referee the last centimetre of a legitimate step.
//
// walk_budget covers sprint-jumping downhill, fly_budget the faster creative
// flight, and fall_budget terminal velocity, which is the fastest anything
// moves straight down without help.
const walk_budget_per_tick = f32(0.8)
const fly_budget_per_tick = f32(2.0)
const fall_budget_per_tick = f32(4.0)

// speed_effect_bonus is how much of the horizontal budget each Speed level
// adds, matching the effect's own movement multiplier.
const speed_effect_bonus = f32(0.2)

// movement_budget_slack is the head start every report gets regardless of how
// long it has been since the last one, so a single delayed packet or a
// knockback landing between two reports is not read as a teleport.
const movement_budget_slack = f32(2.0)

// max_movement_budget_ticks caps how much a long gap between reports can add
// up to. Without it a player idle for a minute would be allowed one arbitrarily
// long jump the moment they move again.
const max_movement_budget_ticks = i64(20)

// tick_duration_ms is how long one simulated tick lasts. The budget is earned
// against the clock rather than against the world's tick counter: reports are
// coalesced, and a world actor falling behind must not shrink the allowance a
// client has legitimately earned in the meantime.
const tick_duration_ms = i64(50)

// validate_movement reports whether a client's newly reported position is one
// it could have reached from where the server last had it, in the time that
// has passed. A report that fails is not applied: the caller sends the player
// back to the position the server does believe in.
//
// It runs on the owning world's actor thread, where the previous position and
// the tick it was accepted at are both stable.
fn (mut s NetworkSession) validate_movement(position types.Vector3, now_ms i64) bool {
	if !s.spawned || s.player.game_mode() == .spectator {
		return true
	}
	previous := s.player.position()
	elapsed := s.movement_elapsed_ticks(now_ms)
	horizontal := math.sqrtf(square(position.x - previous.x) + square(position.z - previous.z))
	vertical := math.abs(position.y - previous.y)
	return horizontal <= s.horizontal_budget(elapsed) && vertical <= vertical_budget(elapsed)
}

// movement_elapsed_ticks is how many ticks of budget this report has earned,
// bounded so a long idle stretch cannot be banked.
fn (mut s NetworkSession) movement_elapsed_ticks(now_ms i64) i64 {
	previous_ms := s.last_movement_ms
	s.last_movement_ms = now_ms
	if previous_ms <= 0 || now_ms <= previous_ms {
		return 1
	}
	elapsed := (now_ms - previous_ms) / tick_duration_ms
	if elapsed < 1 {
		return 1
	}
	return math.min(elapsed, max_movement_budget_ticks)
}

// movement_clock_ms is the wall clock the travel budget is measured against.
fn movement_clock_ms() i64 {
	return time.now().unix_milli()
}

fn (s &NetworkSession) horizontal_budget(elapsed_ticks i64) f32 {
	mut per_tick := if s.player.game_mode().allows_flying() {
		fly_budget_per_tick
	} else {
		walk_budget_per_tick
	}
	if speed := s.player.effect(effect.speed) {
		per_tick *= 1.0 + speed_effect_bonus * f32(speed.level())
	}
	return per_tick * f32(elapsed_ticks) + movement_budget_slack
}

fn vertical_budget(elapsed_ticks i64) f32 {
	return fall_budget_per_tick * f32(elapsed_ticks) + movement_budget_slack
}

fn square(v f32) f32 {
	return v * v
}

// Attack reach, squared, measured from the attacker's eyes. Survival is the
// vanilla three blocks with a block of slack for the gap between where a
// client says it is and where the server last agreed; creative reaches
// further, as it does in game.
const survival_attack_reach_sq = f32(4.0 * 4.0)
const creative_attack_reach_sq = f32(6.0 * 6.0)

// attack_reach_sq returns the squared attack reach for a game mode.
fn attack_reach_sq(mode player.Gamemode) f32 {
	return if mode == .creative { creative_attack_reach_sq } else { survival_attack_reach_sq }
}
