module session

import protocol
import protocol.types
import server.event

// MovementSnapshot is the latest client reported movement waiting to be
// applied by the owning world runtime.
struct MovementSnapshot {
	position types.Vector3
	pitch    f32
	yaw      f32
	head_yaw f32
}

// update_movement replaces the pending movement snapshot and schedules one
// PlayerMoveTask if none is already queued. movement_scheduled must be set
// before submission to prevent a lost wakeup if the actor processes the task
// immediately. Routes to whichever world the session is bound to right now.
fn (mut s NetworkSession) update_movement(position types.Vector3, pitch f32, yaw f32, head_yaw f32) {
	if !s.spawned {
		return
	}
	s.movement_mutex.lock()
	s.pending_movement = MovementSnapshot{position, pitch, yaw, head_yaw}
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

// effective_position returns the latest position reported by this session,
// including pending movement that the owning world runtime has not applied
// yet. Use it only for validation that must reflect the acting client's latest
// update.
pub fn (s &NetworkSession) effective_position() types.Vector3 {
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
fn (t PlayerMoveTask) run(mut tx WorldTx) {
	mut s := tx.wr.hub.session_by_runtime(t.runtime_id) or { return }
	for {
		if s.world_binding().epoch != t.epoch || t.runtime_id !in tx.wr.players {
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
			s.deliver(&protocol.MovePlayerPacket{
				actor_runtime_id: s.runtime_id
				position:         current.position
				pitch:            current.pitch
				yaw:              current.yaw
				head_yaw:         current.head_yaw
				mode:             1
				on_ground:        false
			})
			return
		}
	}
	s.player.apply_movement(position, snapshot.pitch, snapshot.yaw, snapshot.head_yaw)
	if s.spawned {
		tx.wr.broadcast_world_except(s.runtime_id, s.move_actor_packet())
	}
	s.stream_chunks_if_moved()
}
