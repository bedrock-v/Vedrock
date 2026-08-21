module session

import math
import protocol.types
import server.block
import server.effect
import server.event
import server.item
import server.world
import protocol.current as proto

// break_fx_interval_ticks is how often the punch particle and the arm swing
// repeat while a player keeps mining the same block.
const break_fx_interval_ticks = 5

// break_progress_tolerance_ticks absorbs the client predicting the block
// destroyed slightly before the server's own progress reaches one.
const break_progress_tolerance_ticks = f32(2.0)

// break_crack_scale is the range the client expects for the crack speed sent
// with the block cracking level events.
const break_crack_scale = f32(65535.0)

// haste_speed_per_level is the mining speed haste adds per level.
const haste_speed_per_level = f32(0.2)

// in_air_break_penalty and submerged_break_penalty are the divisors vanilla
// applies to mining speed off the ground and with the head in water.
const in_air_break_penalty = f32(5.0)
const submerged_break_penalty = f32(5.0)

// ground_probe_depth is how far below the feet the support block is looked up.
// It only has to clear the floating point gap between a player standing on a
// block and that block's top face.
const ground_probe_depth = f32(0.1)

// breaking_snapshot returns a copy of the block this session is currently
// mining. The state is written by the session thread and advanced by the
// owning world thread, so both go through breaking_mutex.
fn (s &NetworkSession) breaking_snapshot() ?BreakProgress {
	mut m := s.breaking_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return s.breaking
}

fn (mut s NetworkSession) set_breaking(progress ?BreakProgress) {
	s.breaking_mutex.lock()
	s.breaking = progress
	s.breaking_mutex.unlock()
}

// breaking_identity_matches reports whether current and expected refer to the
// same tracked break: same position and the same started_tick, which is set
// once when a break starts and never changes afterward.
fn breaking_identity_matches(current BreakProgress, expected BreakProgress) bool {
	return current.x == expected.x && current.y == expected.y && current.z == expected.z
		&& current.started_tick == expected.started_tick
}

// clear_breaking_if_current clears the tracked break only if it is still the
// one identified by expected and reports whether it did. tick_breaking reads
// a snapshot, does its own work, then writes back at the end; without this
// check a session-thread start_break/continue_break/abort_break landing in
// that window would have its new state wiped out by tick_breaking's stale
// write instead of being left alone.
fn (mut s NetworkSession) clear_breaking_if_current(expected BreakProgress) bool {
	s.breaking_mutex.lock()
	defer {
		s.breaking_mutex.unlock()
	}
	current := s.breaking or { return false }
	if !breaking_identity_matches(current, expected) {
		return false
	}
	s.breaking = none
	return true
}

// swap_breaking_if_current replaces the tracked break with updated only if it
// is still the one identified by expected and reports whether it did. Same
// reasoning as clear_breaking_if_current.
fn (mut s NetworkSession) swap_breaking_if_current(expected BreakProgress, updated BreakProgress) bool {
	s.breaking_mutex.lock()
	defer {
		s.breaking_mutex.unlock()
	}
	current := s.breaking or { return false }
	if !breaking_identity_matches(current, expected) {
		return false
	}
	s.breaking = updated
	return true
}

// broadcast_cracking routes one block cracking level event through the world
// runtime this session is bound to, so it reaches that world's players only.
// The event is dropped when the session has no bound world.
fn (mut s NetworkSession) broadcast_cracking(event_id int, pos types.BlockPosition, data int) {
	binding := s.world_binding()
	if isnil(binding.world_runtime) {
		return
	}
	mut wr := binding.world_runtime
	wr.submit(BlockCrackingTask{
		session_runtime_id: s.runtime_id
		epoch:              binding.epoch
		event_id:           event_id
		pos:                pos
		data:               data
	})
}

// BlockCrackingTask broadcasts a cracking animation on the owning world actor.
// The session runtime id and binding epoch are captured at submission time, so
// an event queued just before a world change is discarded instead of animating
// a block in a world the player has already left.
struct BlockCrackingTask {
	session_runtime_id u64
	epoch              i64
	event_id           int
	pos                types.BlockPosition
	data               int
}

fn (t BlockCrackingTask) name() string {
	return 'BlockCrackingTask'
}

fn (t BlockCrackingTask) run(mut tx WorldTx) {
	tx.player_for_epoch(t.session_runtime_id, t.epoch) or { return }
	tx.broadcast_cracking(t.event_id, t.pos, t.data)
}

// StartBreakAnimationTask emits both animations a mining start produces - the
// initial crack and the arm swing - in one pass over the world's players.
struct StartBreakAnimationTask {
	session_runtime_id u64
	epoch              i64
	pos                types.BlockPosition
	crack_speed        int
}

fn (t StartBreakAnimationTask) name() string {
	return 'StartBreakAnimationTask'
}

fn (t StartBreakAnimationTask) run(mut tx WorldTx) {
	s := tx.player_for_epoch(t.session_runtime_id, t.epoch) or { return }
	if t.crack_speed > 0 {
		tx.broadcast_cracking(proto.level_event_start_block_cracking, t.pos, t.crack_speed)
	}
	tx.broadcast_swing(s)
}

fn (mut s NetworkSession) handle_start_break(pos types.BlockPosition, click_face int) {
	if s.player.is_dead() || !s.can_interact() {
		s.log.debug('BREAK-DIAG: handle_start_break(${pos.x},${pos.y},${pos.z}) dropped: dead=${s.player.is_dead()} can_interact=${s.can_interact()}')
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	if old_id == world.air.network_id {
		s.log.debug('BREAK-DIAG: handle_start_break(${pos.x},${pos.y},${pos.z}) dropped: block_at reports air')
		s.resend_block(pos)
		return
	}
	if !s.within_place_reach(pos) {
		s.log.debug('BREAK-DIAG: handle_start_break(${pos.x},${pos.y},${pos.z}) dropped: out of reach, own_pos=${s.effective_position()}')
		return
	}
	mut ctx := event.new_context(event.StartBreakData{
		player: s
		x:      pos.x
		y:      pos.y
		z:      pos.z
		face:   click_face
	})
	s.hub.events.start_break(mut ctx)
	if ctx.is_cancelled() {
		s.log.debug('BREAK-DIAG: handle_start_break(${pos.x},${pos.y},${pos.z}) dropped: start_break event cancelled')
		s.resend_block(pos)
		return
	}
	speed := s.break_progress_per_tick(old_id)
	s.log.debug('BREAK-DIAG: handle_start_break(${pos.x},${pos.y},${pos.z}) tracking old_id=${old_id} speed=${speed}')
	s.set_breaking(BreakProgress{
		x:            pos.x
		y:            pos.y
		z:            pos.z
		block_id:     old_id
		started_tick: s.hub.current_tick()
		face:         click_face
		speed:        speed
	})
	if punchable := s.hub.blocks.get(old_id) {
		if punchable is block.Punchable {
			mut wld := s.current_world()
			if !isnil(wld) {
				punchable.punch(pos.x, pos.y, pos.z, click_face, mut wld)
			}
		}
	}
	binding := s.world_binding()
	if isnil(binding.world_runtime) {
		return
	}
	mut wr := binding.world_runtime
	wr.submit(StartBreakAnimationTask{
		session_runtime_id: s.runtime_id
		epoch:              binding.epoch
		pos:                pos
		crack_speed:        int(break_crack_scale * speed)
	})
}

fn (mut s NetworkSession) handle_continue_break(pos types.BlockPosition, click_face int) {
	if bp := s.breaking_snapshot() {
		if bp.x == pos.x && bp.y == pos.y && bp.z == pos.z {
			return
		}
		s.broadcast_cracking(proto.level_event_stop_block_cracking, types.BlockPosition{bp.x, bp.y, bp.z},
			0)
	}
	s.handle_start_break(pos, click_face)
}

fn (mut s NetworkSession) handle_abort_break(pos types.BlockPosition) {
	s.set_breaking(none)
	s.broadcast_cracking(proto.level_event_stop_block_cracking, pos, 0)
}

// tick_breaking advances the block this player is mining by one tick and
// keeps the client's crack animation in sync, since the client leaves the
// break timing to the server. It runs on the owning world's thread.
fn (mut s NetworkSession) tick_breaking(mut tx WorldTx) {
	original := s.breaking_snapshot() or { return }
	pos := types.BlockPosition{original.x, original.y, original.z}
	current_id := tx.block_at(original.x, original.y, original.z)
	if s.player.is_dead() || !s.can_interact() || !s.within_place_reach(pos)
		|| current_id != original.block_id {
		s.log.debug('BREAK-DIAG: tick_breaking(${pos.x},${pos.y},${pos.z}) clearing: dead=${s.player.is_dead()} can_interact=${s.can_interact()} in_reach=${s.within_place_reach(pos)} tracked_id=${original.block_id} current_id=${current_id}')
		if s.clear_breaking_if_current(original) {
			tx.broadcast_stop_cracking(original.x, original.y, original.z)
		}
		return
	}

	mut bp := original
	speed := s.break_progress_per_tick(bp.block_id)
	speed_changed := math.abs(speed - bp.speed) > 0.0001
	bp.speed = speed
	bp.progress += speed

	// The client hands block breaking to the server (see the start game
	// server_authoritative_block_breaking flag), so reaching full progress is
	// what actually destroys the block. Without this the crack animation runs
	// forever and the block is never removed.
	if bp.progress >= 1.0 {
		if s.clear_breaking_if_current(original) {
			tx.complete_block_break(mut s, pos, bp.block_id)
		}
		return
	}

	send_fx := bp.fx_ticker % break_fx_interval_ticks == 0
	bp.fx_ticker++

	if !s.swap_breaking_if_current(original, bp) {
		// A session-thread start_break/continue_break/abort_break replaced or
		// cleared the tracked break between the read at the top of this
		// function and here. This tick's contribution belongs to a break that
		// no longer exists.
		s.log.debug('BREAK-DIAG: tick_breaking(${pos.x},${pos.y},${pos.z}) swap rejected: session-thread break state changed mid-tick')
		return
	}
	if speed_changed {
		tx.broadcast_crack_speed(pos, int(break_crack_scale * speed))
	}
	if send_fx {
		tx.broadcast_punch_particle(pos, bp.block_id, bp.face)
		tx.broadcast_swing(s)
	}
}

// break_complete reports whether the tracked progress is far enough along for
// a client predicted destroy to be accepted for pos. Blocks that break within
// the tolerance window are accepted without tracked progress at all, since the
// client destroys those before it ever reports a start action.
fn (s &NetworkSession) break_complete(pos types.BlockPosition, block_id int) bool {
	speed := s.break_progress_per_tick(block_id)
	bp := s.breaking_snapshot() or {
		result := speed * break_progress_tolerance_ticks >= 1.0
		s.log.debug('BREAK-DIAG: break_complete(${pos.x},${pos.y},${pos.z}) no tracked progress, tolerance check speed=${speed} -> ${result}')
		return result
	}
	if bp.x != pos.x || bp.y != pos.y || bp.z != pos.z || bp.block_id != block_id {
		result := speed * break_progress_tolerance_ticks >= 1.0
		s.log.debug('BREAK-DIAG: break_complete(${pos.x},${pos.y},${pos.z}) tracked progress is for a different block/pos (tracked=${bp.x},${bp.y},${bp.z} id=${bp.block_id} vs requested id=${block_id}), tolerance check -> ${result}')
		return result
	}
	result := bp.progress + bp.speed * break_progress_tolerance_ticks >= 1.0
	if !result {
		s.log.debug('BREAK-DIAG: break_complete(${pos.x},${pos.y},${pos.z}) progress=${bp.progress} speed=${bp.speed} not yet complete')
	}
	return result
}

// can_harvest reports whether the held item is the right tool to make the
// block drop anything, the same check vanilla runs before spawning drops.
fn (s &NetworkSession) can_harvest(runtime_id int) bool {
	tool_type, harvest_level, _ := s.held_mining_stats()
	return s.hub.blocks.break_info(runtime_id).tool_compatible(tool_type, harvest_level)
}

// break_progress_per_tick is the fraction of the block broken each tick. The
// base time comes from the block's hardness and the held tool, then the
// player's own state scales it, mirroring vanilla. Efficiency and aqua
// affinity enchantments are not modelled yet.
fn (s &NetworkSession) break_progress_per_tick(runtime_id int) f32 {
	info := s.hub.blocks.break_info(runtime_id)
	if !info.breakable() {
		return 0.0
	}
	tool_type, harvest_level, efficiency := s.held_mining_stats()
	mut ticks := info.break_seconds(tool_type, harvest_level, efficiency) * f32(effect.ticks_per_second)
	if !s.supported_by_ground() && s.player.game_mode() != proto.game_type_creative {
		ticks *= in_air_break_penalty
	}
	if s.head_submerged() {
		ticks *= submerged_break_penalty
	}
	if ticks <= 0 {
		return 1.0
	}
	mut progress := 1.0 / ticks
	if haste := s.player.effect(effect.haste) {
		progress *= 1.0 + haste_speed_per_level * f32(haste.level())
	}
	if fatigue := s.player.effect(effect.mining_fatigue) {
		progress *= mining_fatigue_multiplier(fatigue.level())
	}
	return progress
}

// mining_fatigue_multiplier is the mining speed left at each fatigue level.
// The drop is a fixed table rather than a curve, so the values are listed as
// vanilla defines them instead of being derived.
fn mining_fatigue_multiplier(level int) f32 {
	return match level {
		1 { f32(0.3) }
		2 { f32(0.09) }
		3 { f32(0.0027) }
		else { f32(0.00081) }
	}
}

// held_mining_stats returns the tool family, harvest level and mining
// efficiency of the held item. Bare hands and non tools mine everything at
// efficiency one.
fn (s &NetworkSession) held_mining_stats() (int, int, f32) {
	_, name := s.held_stack_and_name()
	held := s.hub.items.get(name) or {
		return block.tool_type_none, block.harvest_level_none, f32(1.0)
	}
	efficiency := held.mining_speed()
	if held is item.MiningTool {
		return held.block_tool_type(), held.harvest_level(), efficiency
	}
	return block.tool_type_none, block.harvest_level_none, efficiency
}

// supported_by_ground reports whether a block is holding the player up.
//
// The in air mining penalty is a factor of five, so gating it on the client's
// own ground flag makes every block take five times as long whenever that flag
// is not reported the way the server expects, which is the whole difference
// between a block breaking and a block that never finishes. PocketMine-MP does
// not take its ground state from the input flags either, so the support block
// is looked up here instead. Liquids do not hold a player up.
fn (s &NetworkSession) supported_by_ground() bool {
	pos := s.current_position()
	below := s.block_at(int(math.floor(pos.x)), int(math.floor(pos.y - ground_probe_depth)),
		int(math.floor(pos.z)))
	return below != world.air.network_id && below != world.water.network_id
}

// head_submerged reports whether the player's eyes are inside water, which
// slows mining down the same way vanilla does.
fn (s &NetworkSession) head_submerged() bool {
	pos := s.current_position()
	return s.block_at(int(math.floor(pos.x)), int(math.floor(pos.y + player_eye_height)),
		int(math.floor(pos.z))) == world.water.network_id
}
