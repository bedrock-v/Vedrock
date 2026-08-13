module session

import math
import protocol.types
import server.block
import server.effect
import server.event
import server.item
import server.internal.network
import server.world

// break_fx_interval_ticks is how often the punch particle and the arm swing
// repeat while a player keeps mining the same block.
const break_fx_interval_ticks = 5

// break_progress_tolerance_ticks absorbs the client predicting the block
// destroyed slightly before the server's own progress reaches one.
const break_progress_tolerance_ticks = f32(2.0)

// break_crack_scale is the range the client expects for the crack speed sent
// with the block cracking level events.
const break_crack_scale = f32(65535.0)

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

fn (mut s NetworkSession) handle_start_break(pos types.BlockPosition, click_face int) {
	if s.player.is_dead() || !s.can_interact() {
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	if old_id == world.air.network_id {
		s.resend_block(pos)
		return
	}
	if !s.within_place_reach(pos) {
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
		s.resend_block(pos)
		return
	}
	speed := s.break_progress_per_tick(old_id)
	s.set_breaking(BreakProgress{
		x:            pos.x
		y:            pos.y
		z:            pos.z
		block_id:     old_id
		started_tick: s.hub.current_tick()
		face:         click_face
		speed:        speed
	})
	if speed > 0 {
		s.broadcast_cracking(network.level_event_start_block_cracking, pos,
			int(break_crack_scale * speed))
	}
	if punchable := s.hub.blocks.get(old_id) {
		if punchable is block.Punchable {
			mut wld := s.current_world()
			if !isnil(wld) {
				punchable.punch(pos.x, pos.y, pos.z, click_face, mut wld)
			}
		}
	}
	s.broadcast_swing()
}

fn (mut s NetworkSession) handle_continue_break(pos types.BlockPosition, click_face int) {
	if bp := s.breaking_snapshot() {
		if bp.x == pos.x && bp.y == pos.y && bp.z == pos.z {
			return
		}
		s.broadcast_cracking(network.level_event_stop_block_cracking, types.BlockPosition{bp.x, bp.y, bp.z},
			0)
	}
	s.handle_start_break(pos, click_face)
}

fn (mut s NetworkSession) handle_abort_break(pos types.BlockPosition) {
	s.set_breaking(none)
	s.broadcast_cracking(network.level_event_stop_block_cracking, pos, 0)
}

// tick_breaking advances the block this player is mining by one tick and
// keeps the client's crack animation in sync, since the client leaves the
// break timing to the server. It runs on the owning world's thread.
fn (mut s NetworkSession) tick_breaking(mut tx WorldTx) {
	mut bp := s.breaking_snapshot() or { return }
	pos := types.BlockPosition{bp.x, bp.y, bp.z}
	if s.player.is_dead() || !s.can_interact() || !s.within_place_reach(pos)
		|| tx.block_at(bp.x, bp.y, bp.z) != bp.block_id {
		s.set_breaking(none)
		tx.broadcast_stop_cracking(bp.x, bp.y, bp.z)
		return
	}
	speed := s.break_progress_per_tick(bp.block_id)
	if math.abs(speed - bp.speed) > 0.0001 {
		bp.speed = speed
		tx.broadcast_crack_speed(pos, int(break_crack_scale * speed))
	}
	bp.progress += speed
	if bp.fx_ticker % break_fx_interval_ticks == 0 && bp.progress < 1.0 {
		tx.broadcast_punch_particle(pos, bp.block_id, bp.face)
		tx.broadcast_swing(s)
	}
	bp.fx_ticker++
	s.set_breaking(bp)
}

// break_complete reports whether the tracked progress is far enough along for
// a client predicted destroy to be accepted for pos. Blocks that break within
// the tolerance window are accepted without tracked progress at all, since the
// client destroys those before it ever reports a start action.
fn (s &NetworkSession) break_complete(pos types.BlockPosition, block_id int) bool {
	speed := s.break_progress_per_tick(block_id)
	bp := s.breaking_snapshot() or { return speed * break_progress_tolerance_ticks >= 1.0 }
	if bp.x != pos.x || bp.y != pos.y || bp.z != pos.z || bp.block_id != block_id {
		return speed * break_progress_tolerance_ticks >= 1.0
	}
	return bp.progress + bp.speed * break_progress_tolerance_ticks >= 1.0
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
	if !s.player.on_ground() && s.player.game_mode() != network.game_type_creative {
		ticks *= 5
	}
	if s.head_submerged() {
		ticks *= 5
	}
	if ticks <= 0 {
		return 1.0
	}
	mut progress := 1.0 / ticks
	if haste := s.player.effect(effect.haste) {
		level := f64(haste.level())
		progress *= f32((1.0 + 0.2 * level) * math.pow(1.2, level))
	}
	if fatigue := s.player.effect(effect.mining_fatigue) {
		progress *= f32(math.pow(0.21, f64(fatigue.level())))
	}
	return progress
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

// head_submerged reports whether the player's eyes are inside water, which
// slows mining down the same way vanilla does.
fn (s &NetworkSession) head_submerged() bool {
	pos := s.current_position()
	return s.block_at(int(math.floor(pos.x)), int(math.floor(pos.y + player_eye_height)),
		int(math.floor(pos.z))) == world.water.network_id
}
