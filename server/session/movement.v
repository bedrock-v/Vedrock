module session

import math
import protocol.version.v2168.packets as packets_2168
import protocol.version.v2168.enums as enums_2168
import protocol.types
import server.event
import server.internal.network

// MovementSnapshot is the latest client reported movement waiting to be
// applied by the owning world runtime.
struct MovementSnapshot {
	position  types.Vector3
	pitch     f32
	yaw       f32
	head_yaw  f32
	on_ground bool
}

// update_movement replaces the pending movement snapshot and schedules one
// PlayerMoveTask if none is already queued. movement_scheduled must be set
// before submission to prevent a lost wakeup if the actor processes the task
// immediately. Routes to whichever world the session is bound to right now.
//
// on_ground is the client reported ground state, trusted like every other
// movement field here.
fn (mut s NetworkSession) update_movement(position types.Vector3, pitch f32, yaw f32, head_yaw f32, on_ground bool) {
	if !s.spawned {
		return
	}
	sanitized_position, sanitized_pitch, sanitized_yaw, sanitized_head_yaw := s.sanitize_movement(position,
		pitch, yaw, head_yaw)
	s.movement_mutex.lock()
	s.pending_movement =
		MovementSnapshot{sanitized_position, sanitized_pitch, sanitized_yaw, sanitized_head_yaw, on_ground}
	if s.movement_scheduled {
		s.movement_mutex.unlock()
		return
	}
	s.movement_scheduled = true
	s.movement_mutex.unlock()

	binding := s.world_binding()
	mut submitted := false
	if !isnil(binding.world_runtime) {
		mut wr := binding.world_runtime
		submitted = wr.try_submit(PlayerMoveTask{
			runtime_id: s.runtime_id
			epoch:      binding.epoch
		})
	}
	if !submitted {
		// No world runtime bound yet, queue full, or the world is stopping:
		// allow a later movement packet to retry.
		s.movement_mutex.lock()
		s.movement_scheduled = false
		s.movement_mutex.unlock()
	}
}

// sanitize_movement replaces non-finite position or rotation components
// with the session's last valid values. This prevents NaN or infinity from
// entering player state and bypassing checks such as attack reach.
fn (mut s NetworkSession) sanitize_movement(position types.Vector3, pitch f32, yaw f32, head_yaw f32) (types.Vector3, f32, f32, f32) {
	current := s.player.movement()
	mut pos := position
	mut p := pitch
	mut y := yaw
	mut hy := head_yaw
	if !is_finite32(pos.x) {
		pos.x = current.position.x
	}
	if !is_finite32(pos.y) {
		pos.y = current.position.y
	}
	if !is_finite32(pos.z) {
		pos.z = current.position.z
	}
	if !is_finite32(p) {
		p = current.pitch
	}
	if !is_finite32(y) {
		y = current.yaw
	}
	if !is_finite32(hy) {
		hy = current.head_yaw
	}
	return pos, p, y, hy
}

fn is_finite32(f f32) bool {
	v := f64(f)
	return !math.is_nan(v) && !math.is_inf(v, 0)
}

// effective_position returns the latest position reported by this session,
// including pending movement that the owning world runtime has not applied
// yet. Use it only for validation that must reflect the acting client's latest
// update.
fn (s &NetworkSession) effective_position() types.Vector3 {
	mut mtx := s.movement_mutex
	mtx.lock()
	defer {
		mtx.unlock()
	}
	if snap := s.pending_movement {
		return snap.position
	}
	return s.player.position()
}

// take_pending_movement atomically returns and clears the pending snapshot.
fn (mut s NetworkSession) take_pending_movement() ?MovementSnapshot {
	s.movement_mutex.lock()
	defer {
		s.movement_mutex.unlock()
	}
	snap := s.pending_movement or { return none }
	s.pending_movement = none
	return snap
}

fn (mut s NetworkSession) clear_movement_scheduled_if_idle() bool {
	s.movement_mutex.lock()
	defer {
		s.movement_mutex.unlock()
	}
	if s.pending_movement == none {
		s.movement_scheduled = false
		return true
	}
	return false
}

// PlayerMoveTask is update_movement's actual application, running entirely
// on the owning world's own actor.
struct PlayerMoveTask {
	runtime_id u64
	epoch      i64
}

// run resolves the session through Hub because stale tasks must still clear
// movement_scheduled even after the player leaves this world or its epoch changes.
// The lookup happens once per coalesced movement batch, not per packet.
fn (t PlayerMoveTask) name() string {
	return 'PlayerMoveTask'
}

fn (t PlayerMoveTask) run(mut tx WorldTx) {
	mut s := tx.wr.hub.session_by_runtime(t.runtime_id) or { return }
	for {
		if s.world_binding().epoch != t.epoch || !tx.wr.entities.is_player_actor(t.runtime_id) {
			s.movement_mutex.lock()
			s.movement_scheduled = false
			s.movement_mutex.unlock()
			return
		}
		snapshot := s.take_pending_movement() or { return }
		s.apply_movement(mut tx, snapshot)
		if s.clear_movement_scheduled_if_idle() {
			return
		}
	}
}

fn (mut s NetworkSession) apply_movement(mut tx WorldTx, snapshot MovementSnapshot) {
	position := snapshot.position
	if s.spawned && tx.wr.hub.current_tick() % 40 == 0 {
		s.log.debug('move ${s.player.identity.display_name} pos=(${position.x:.2f}, ${position.y:.2f}, ${position.z:.2f})')
	}
	if s.spawned && tx.wr.events.len() > 0 {
		mut ctx := event.new_context(event.MoveData{
			player: s
			x:      position.x
			y:      position.y
			z:      position.z
		})
		tx.wr.events.player_move(mut ctx)
		if ctx.is_cancelled() {
			current := s.player.movement()
			mut move_packet := &packets_2168.MovePlayerPacket{
				player_runtime_id: network.actor_runtime_id(s.runtime_id)
				y_head_rotation:   current.head_yaw
				position_mode:     enums_2168.PlayerPositionMode.respawn
				on_ground:         false
			}
			move_packet.position[0] = current.position.x
			move_packet.position[1] = current.position.y
			move_packet.position[2] = current.position.z
			move_packet.rotation[0] = current.pitch
			move_packet.rotation[1] = current.yaw
			s.deliver(move_packet)
			return
		}
	}
	landed_distance := s.player.apply_movement(position, snapshot.pitch, snapshot.yaw,
		snapshot.head_yaw, snapshot.on_ground)
	if s.spawned {
		tx.wr.broadcast_world_except(s.runtime_id, s.move_actor_packet())
	}
	s.apply_fall_damage(mut tx.wr, landed_distance)
	s.stream_chunks_if_moved()
}

const fall_damage_safe_distance = f32(3.0)

fn fall_damage_amount(fall_distance f32) f32 {
	over := fall_distance - fall_damage_safe_distance
	if over <= 0 {
		return 0
	}
	whole := f32(int(over))
	if over > whole {
		return whole + 1
	}
	return whole
}

fn (mut s NetworkSession) apply_fall_damage(mut wr WorldRuntime, landed_distance f32) {
	dmg := fall_damage_amount(landed_distance)
	if dmg > 0 {
		s.apply_hurt(mut wr, dmg, FallDamageSource{})
	}
}
