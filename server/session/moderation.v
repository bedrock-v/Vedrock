module session

import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import server.internal.logger
import server.worldrt

// op / deop

fn (mut h Hub) set_operator(mut target NetworkSession, value bool) {
	target.player.perm.set_op(value)
	h.config_mutex.lock()
	if value {
		h.ops.add(target.player.identity.display_name) or {
			h.config_mutex.unlock()
			target.log.warn('Failed to persist op for ${target.player.identity.display_name}: ${err}')
			target.refresh_op_state()
			return
		}
	} else {
		h.ops.remove(target.player.identity.display_name) or {
			h.config_mutex.unlock()
			target.log.warn('Failed to persist deop for ${target.player.identity.display_name}: ${err}')
			target.refresh_op_state()
			return
		}
	}
	h.config_mutex.unlock()
	target.refresh_op_state()
}

// is_op is the locked read path used by login and runtime permission checks.
fn (mut h Hub) is_op(name string) bool {
	h.config_mutex.lock()
	defer {
		h.config_mutex.unlock()
	}
	return h.ops.is_op(name)
}

// set_operator grants or revokes operator status. Hub owns the op list,
// this is a handoff rather than a bridge onto a world actor.
fn (mut s NetworkSession) set_operator(value bool) {
	s.hub.set_operator(mut s, value)
}

// PlayerOpRefreshTask resends commands and abilities on the target's owning
// world.
struct PlayerOpRefreshTask {
	runtime_id u64
	epoch      i64
	result     chan bool = chan bool{cap: 1}
}

fn (t PlayerOpRefreshTask) name() string {
	return 'PlayerOpRefreshTask'
}

fn (t PlayerOpRefreshTask) run(mut tx worldrt.WorldTx) {
	mut applied := false
	defer {
		t.result <- applied
	}
	mut target := player_for_epoch(mut tx, t.runtime_id, t.epoch) or { return }
	target.refresh_available_commands()
	target.refresh_abilities()
	applied = true
}

// refresh_op_state retries once if the player changes worlds between reading
// the binding and the refresh task running.
fn (mut s NetworkSession) refresh_op_state() {
	if s.try_refresh_op_state_once() {
		return
	}
	s.try_refresh_op_state_once()
}

// try_refresh_op_state_once submits against the current binding and reports
// whether the task actually applied.
fn (mut s NetworkSession) try_refresh_op_state_once() bool {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return false
	}
	task := PlayerOpRefreshTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
	}
	if !wr.submit(task) {
		return false
	}
	return <-task.result
}

// kill takes the player through the normal death path with no attacker.
//
// It is one of the command entry bridges in this file. A command runs on the
// session thread and holds no transaction, so it can't reach a Player verb
// directly: each bridge enters the owning world's actor, reresolves the
// player against the membership epoch it started from and calls the verb
// there. They stay tx-less on purpose.
//
// Taking a transaction would push the requirement back onto a caller that has
// no way to be holding one.
fn (mut s NetworkSession) kill() {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	worldrt.world_call[bool]('Player.kill', mut wr, fn [rid, epoch] (mut tx worldrt.WorldTx) bool {
		mut target := player_for_epoch(mut tx, rid, epoch) or { return false }
		target.player.kill(mut tx)
		return true
	}) or { false }
}

// position is where the player is right now. It reads session state rather
// than entering the world actor and it is not one of the bridges.
fn (mut s NetworkSession) position() types.Vector3 {
	return s.current_position()
}

// place_water targets the default world through Hub's block API.
fn (mut s NetworkSession) place_water(x int, y int, z int) {
	s.hub.place_water(x, y, z)
}

// request_teleport completes the binding and position update synchronously.
// Chunk resend after a world switch runs asynchronously so a large resend does
// not block the caller.
fn (mut s NetworkSession) request_teleport(x f32, y f32, z f32, world_name string) {
	if world_name != '' && world_name != s.world_name() {
		if !s.change_world(world_name, x, y, z) {
			return
		}
		s.submit_teleport(x, y, z)
		// Chunk transmission (up to a few hundred packets) runs on its own
		// thread so it never stalls whichever thread called teleport.
		spawn s.reload_chunks(s.cfg.view_distance)
		return
	}
	s.submit_teleport(x, y, z)
}

// submit_teleport arms the teleport acknowledgement and runs the move on the
// world that owns the player, blocking until it has happened.
//
// It blocks because teleport reads as immediate to its caller: a command that
// moves a player and then reports where they are must not race its own move.
//
// The acknowledgement is armed here rather than inside the transaction because
// the client keeps reporting movement in the meantime. Anything it sends
// between now and the move describes a position the server is about to
// overwrite and must not be applied on top of the teleport.
fn (mut s NetworkSession) submit_teleport(x f32, y f32, z f32) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	pos := types.Vector3{x, y, z}
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	s.expect_teleport_ack(pos)
	moved := worldrt.world_call[bool]('Player.teleport', mut wr, fn [rid, epoch, pos] (mut tx worldrt.WorldTx) bool {
		mut target := player_for_epoch(mut tx, rid, epoch) or { return false }
		target.player.teleport(mut tx, pos)
		return true
	}) or { false }
	if !moved {
		// The teleport didn't happen. Release the acknowledgement armed
		// above or the client stays frozen waiting to confirm a position it
		// was never sent.
		s.expect_teleport_ack(s.player.position())
	}
}

// reload_chunks resends the spawn chunks around the player. Runs on its
// own thread after a world switch teleport, so every send here goes
// through the outbound writer like any other gameplay send, never
// directly which would let this thread's writes interleave with the
// writer's on the wire.
fn (mut s NetworkSession) reload_chunks(radius int) {
	logger.name_thread('Chunk Stream/${s.player.identity.display_name}')
	defer {
		logger.unname_thread()
	}
	s.chunk_stream_mutex.lock()
	defer {
		s.chunk_stream_mutex.unlock()
	}
	own := s.player.position()
	s.send_packet(&proto.ChunkRadiusUpdatedPacket{
		chunk_radius: radius
	}) or {}
	s.send_packet(&proto.NetworkChunkPublisherUpdatePacket{
		new_view_position:   proto.BlockPos{
			x: i32(own.x)
			y: i32(own.y)
			z: i32(own.z)
		}
		new_view_radius:     u32(radius * 16)
		server_built_chunks: []proto.ChunkPos{}
	}) or {}
	s.send_spawn_chunks(radius) or {
		s.log.warn('Failed to send chunks after world change: ${err}')
		return
	}
	s.remember_chunk_window(radius)
	s.send_packet(&proto.PlayStatusPacket{
		status: proto.PlayStatus.player_spawn
	}) or {}
}

fn (s &NetworkSession) world_name() string {
	mut m := s.world_mutex
	m.lock()
	defer {
		m.unlock()
	}
	if isnil(s.world) {
		return ''
	}
	return s.world.name
}

// change_world transfers this session between world runtimes. transfer_mutex
// serializes deregister -> rebind -> register so concurrent teleports or
// disconnects cannot leave ghost membership.
fn (mut s NetworkSession) change_world(name string, x f32, y f32, z f32) bool {
	s.transfer_mutex.lock()
	defer {
		s.transfer_mutex.unlock()
	}
	if !s.spawned {
		return false
	}
	mut target_wr := s.hub.world_runtime(name) or { return false }
	target := target_wr.world
	gen := target.make_generator(s.hub.build_generator(target))
	binding := s.world_binding()
	previous := binding.world
	previous_dim := if isnil(previous) { target.dimension.id } else { previous.dimension.id }

	rid := s.runtime_id
	mut previous_wr := binding.world_runtime
	if !isnil(previous_wr) {
		remove_pkt := s.remove_actor_packet()
		list_remove_pkt := s.player_list_remove_packet()
		held_container := s.open_container_position()
		worldrt.world_call[bool]('Session.leave_previous_world', mut previous_wr, fn [rid, remove_pkt, list_remove_pkt, held_container] (mut tx worldrt.WorldTx) bool {
			deregister_player(mut tx, rid)
			if pos := held_container {
				tx.wr.world.release_container_hold(pos.x, pos.y, pos.z, rid)
			}
			tx.wr.broadcast_world_except(rid, remove_pkt)
			tx.wr.broadcast_world_except(rid, list_remove_pkt)
			return true
		}) or {}
	}
	s.set_open_container_position(none)

	s.set_world_binding(target_wr, gen)
	// Position must be updated before the join packets below are built, so
	// add_player_packet reflects where the player actually landed rather
	// than a stale pre transfer position.
	s.player.reset_position(types.Vector3{x, y, z})

	list_add_pkt := s.player_list_add_packet()
	add_player_pkt := s.add_player_packet()
	self := s.self_ref()
	registered := worldrt.world_call[bool]('Session.join_target_world', mut target_wr, fn [rid, self, list_add_pkt, add_player_pkt] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, self)
		tx.wr.broadcast_world_except(rid, list_add_pkt)
		tx.wr.broadcast_world_except(rid, add_player_pkt)
		return true
	}) or { false }
	if !registered {
		// Binding already points at target_wr. If registration is rejected,
		// close the session rather than leave it bound to a world that does
		// not own it.
		s.log.warn('world transfer to "${name}" failed: destination world actor rejected registration (likely stopping) - disconnecting to avoid a half-transferred session')
		s.disconnect('World transfer failed')
		return false
	}

	s.reset_chunk_window()
	if target.dimension.id != previous_dim {
		mut change_packet := &proto.ChangeDimensionPacket{
			dimension_id: target.dimension.id
			respawn:      false
		}
		change_packet.position[0] = x
		change_packet.position[1] = y
		change_packet.position[2] = z
		s.deliver(change_packet)
		s.deliver(&proto.StopSoundPacket{
			sound_name:      ''
			stop_all_sounds: true
		})
		s.deliver(&proto.PlayStatusPacket{
			status: proto.PlayStatus.player_spawn
		})
		s.deliver(&proto.PlayerActionPacket{
			player_runtime_id: proto.actor_runtime_id(s.runtime_id)
			action:            proto.PlayerActionType.change_dimension_ack
		})
		s.expect_teleport_ack(types.Vector3{x, y, z})
	}
	return true
}

// teleport moves the player within the world they are already in. The actor
// work and the blocking are request_teleport's; this is the name a command
// reaches it by.
fn (mut s NetworkSession) teleport(x f32, y f32, z f32) {
	s.request_teleport(x, y, z, '')
}

// teleport_to_world moves the player into another loaded world at the given
// position. No-op if the world is not loaded (change_world's own lookup
// fails and request_teleport returns without side effects).
fn (mut s NetworkSession) teleport_to_world(name string, x f32, y f32, z f32) {
	s.request_teleport(x, y, z, name)
}

// clear_inventory empties the player's inventory. It runs on the owning
// world's actor because the inventory is state that actor owns. Bridge, in the
// sense kill describes.
fn (mut s NetworkSession) clear_inventory() {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	worldrt.world_call[bool]('Player.clear_inventory', mut wr, fn [rid, epoch] (mut tx worldrt.WorldTx) bool {
		mut target := player_for_epoch(mut tx, rid, epoch) or { return false }
		target.player.clear_inventory(mut tx)
		// The worn pieces went with the rest of the inventory, so everyone
		// else has to be told or they keep rendering the old set.
		target.broadcast_armor()
		return true
	}) or { false }
}

// give_item adds count of the item named id to the player's inventory,
// reporting whether it landed. Bridge, in the sense kill describes.
//
// It blocks for the same reason submit_teleport does: the caller is told
// whether the item arrived, so the answer has to describe work that already
// happened rather than work that was only queued.
fn (mut s NetworkSession) give_item(id string, count int) bool {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return false
	}
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	return worldrt.world_call[bool]('Player.give_item', mut wr, fn [rid, epoch, id, count] (mut tx worldrt.WorldTx) bool {
		mut target := player_for_epoch(mut tx, rid, epoch) or { return false }
		return target.player.give_item(mut tx, id, count)
	}) or { false }
}
