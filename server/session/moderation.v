module session

import protocol
import protocol.enums
import protocol.types

// op / deop

pub fn (mut h Hub) set_operator(mut target NetworkSession, value bool) {
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
pub fn (mut h Hub) is_op(name string) bool {
	h.config_mutex.lock()
	defer {
		h.config_mutex.unlock()
	}
	return h.ops.is_op(name)
}

pub fn (mut s NetworkSession) set_operator(value bool) {
	s.hub.set_operator(mut s, value)
}

// PlayerOpRefreshTask resends commands and abilities on the target's owning
// world.
struct PlayerOpRefreshTask {
	runtime_id u64
	epoch      i64
	result     chan bool = chan bool{cap: 1}
}

fn (t PlayerOpRefreshTask) run(mut tx WorldTx) {
	mut applied := false
	defer {
		t.result <- applied
	}
	mut target := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
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

// kill

// PlayerKillTask forces a player through the normal death path without an
// attacker.
struct PlayerKillTask {
	runtime_id u64
	epoch      i64
}

fn (t PlayerKillTask) run(mut tx WorldTx) {
	mut target := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	if target.player.is_dead() {
		return
	}
	target.player.set_health(0)
	target.deliver(target.health_update())
	target.apply_death(mut tx.wr, '%death.attack.generic', [target.player.identity.display_name])
}

pub fn (mut s NetworkSession) kill() {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerKillTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
	})
}

// teleport

pub fn (mut s NetworkSession) position() (f32, f32, f32) {
	p := s.current_position()
	return p.x, p.y, p.z
}

// place_water targets the default world through Hub's block API.
pub fn (mut s NetworkSession) place_water(x int, y int, z int) {
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
		s.apply_teleport(x, y, z)
		// Chunk transmission (up to a few hundred packets) runs on its own
		// thread so it never stalls whichever thread called teleport.
		spawn s.reload_chunks(s.cfg.view_distance)
		return
	}
	s.apply_teleport(x, y, z)
}

// reload_chunks resends the spawn chunks around the player. Runs on its
// own thread after a world switch teleport, so every send here goes
// through the outbound writer like any other gameplay send, never
// directly which would let this thread's writes interleave with the
// writer's on the wire.
fn (mut s NetworkSession) reload_chunks(radius int) {
	s.chunk_stream_mutex.lock()
	defer {
		s.chunk_stream_mutex.unlock()
	}
	own := s.player.position()
	s.send_packet(&protocol.ChunkRadiusUpdatedPacket{
		radius: radius
	}) or {}
	s.send_packet(&protocol.NetworkChunkPublisherUpdatePacket{
		block_position: types.BlockPosition{int(own.x), int(own.y), int(own.z)}
		radius:         radius * 16
		saved_chunks:   []types.ChunkPosition{}
	}) or {}
	s.send_spawn_chunks(radius) or {
		s.log.warn('Failed to send chunks after world change: ${err}')
		return
	}
	s.remember_chunk_window(radius)
	s.send_packet(&protocol.PlayStatusPacket{
		status: 3
	}) or {}
}

pub fn (s &NetworkSession) world_name() string {
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
		world_call[bool](mut previous_wr, fn [rid, remove_pkt, list_remove_pkt] (mut tx WorldTx) bool {
			tx.deregister_player(rid)
			tx.wr.broadcast_world_except(rid, remove_pkt)
			tx.wr.broadcast_world_except(rid, list_remove_pkt)
			return true
		}) or {}
	}

	s.set_world_binding(target_wr, gen)
	// Position must be updated before the join packets below are built, so
	// add_player_packet reflects where the player actually landed rather
	// than a stale pre transfer position.
	s.player.reset_position(types.Vector3{x, y, z})

	list_add_pkt := s.player_list_add_packet()
	add_player_pkt := s.add_player_packet()
	registered := world_call[bool](mut target_wr, fn [rid, s, list_add_pkt, add_player_pkt] (mut tx WorldTx) bool {
		tx.register_player(s)
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

	s.clear_chunk_cache()
	s.reset_chunk_window()
	if target.dimension.id != previous_dim {
		s.deliver(&protocol.ChangeDimensionPacket{
			dimension: target.dimension.id
			position:  types.Vector3{x, y, z}
			respawn:   false
		})
		s.deliver(&protocol.StopSoundPacket{
			sound_name: ''
			stop_all:   true
		})
		s.deliver(&protocol.PlayStatusPacket{
			status: int(enums.PlayStatus.player_spawn)
		})
		s.deliver(&protocol.PlayerActionPacket{
			action:           int(enums.PlayerAction.dimension_change_ack)
			actor_runtime_id: s.runtime_id
		})
	}
	return true
}

// apply_teleport resets the position, sends the correction packet and
// broadcasts the move through the owning world actor. Unlike change_world,
// a same world teleport has no existing world_call to reuse.
fn (mut s NetworkSession) apply_teleport(x f32, y f32, z f32) {
	s.player.reset_position(types.Vector3{x, y, z})
	current := s.player.movement()
	s.deliver(&protocol.MovePlayerPacket{
		actor_runtime_id: s.runtime_id
		position:         current.position
		pitch:            current.pitch
		yaw:              current.yaw
		head_yaw:         current.head_yaw
		mode:             protocol.move_player_mode_teleport
		on_ground:        false
	})
	mut wr := s.current_world_runtime()
	if !isnil(wr) {
		rid := s.runtime_id
		move_pkt := s.move_actor_packet()
		world_call[bool](mut wr, fn [rid, move_pkt] (mut tx WorldTx) bool {
			tx.wr.broadcast_world_except(rid, move_pkt)
			return true
		}) or {}
	}
}

pub fn (mut s NetworkSession) teleport(x f32, y f32, z f32) {
	s.request_teleport(x, y, z, '')
}

// teleport_to_world moves the player into another loaded world at the given
// position. No-op if the world is not loaded (change_world's own lookup
// fails and request_teleport returns without side effects).
pub fn (mut s NetworkSession) teleport_to_world(name string, x f32, y f32, z f32) {
	s.request_teleport(x, y, z, name)
}

// clear inventory

// PlayerClearInventoryTask is clear_inventory() run through the owning
// world's actor.
struct PlayerClearInventoryTask {
	runtime_id u64
	epoch      i64
}

fn (t PlayerClearInventoryTask) run(mut tx WorldTx) {
	mut s := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	s.apply_clear_inventory()
}

fn (mut s NetworkSession) apply_clear_inventory() {
	s.player.clear_inventory()
	mut items := []types.ItemStackWrapper{}
	for _ in 0 .. inventory_slot_count {
		items << empty_stack()
	}
	s.deliver(&protocol.InventoryContentPacket{
		window_id:      inventory_window_id
		items:          items
		container_name: types.FullContainerName{
			container_id: 0
		}
		storage:        empty_stack()
	})
}

pub fn (mut s NetworkSession) clear_inventory() {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerClearInventoryTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
	})
}

// give

// give_slot_count/give_hotbar_next implement a deliberately simplified slot
// pick for /give: the server doesn't currently keep a full slot->stack map in
// sync with client-driven inventory transactions (those are tracked by
// client-assigned network ids, not slot index), so building a "first empty
// slot" search would risk silently colliding with content the client already
// has and thinks the server doesn't know about. Round robining across the
// hotbar (0-8) via a dedicated counter avoids touching that unrelated
// bookkeeping; it can still overwrite a hotbar slot's visible content.
const give_hotbar_size = 9

// PlayerGiveItemTask is give_item() run through the owning world's actor.
struct PlayerGiveItemTask {
	runtime_id       u64
	epoch            i64
	numeric_id       int
	block_runtime_id int
	count            int
}

fn (t PlayerGiveItemTask) run(mut tx WorldTx) {
	mut s := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	s.apply_give_item(t.numeric_id, t.block_runtime_id, t.count)
}

fn (mut s NetworkSession) apply_give_item(numeric_id int, block_runtime_id int, count int) {
	slot := s.give_next_slot % give_hotbar_size
	s.give_next_slot++
	stack := types.ItemStack{
		id:               numeric_id
		meta:             0
		count:            count
		block_runtime_id: block_runtime_id
		raw_extra_data:   []u8{}
	}
	net_id := s.player.track_stack(stack)
	s.player.set_slot(slot, net_id)
	s.send_slot_update(slot, wrap_stack_id(stack, net_id))
}

pub fn (mut s NetworkSession) give_item(id string, count int) bool {
	numeric_id := s.hub.data.item_id(id)
	if numeric_id == 0 && id != 'minecraft:air' {
		return false
	}
	mut block_runtime_id := 0
	if it := s.hub.items.get(id) {
		block_runtime_id = it.block_runtime_id()
	}
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return false
	}
	wr.submit(PlayerGiveItemTask{
		runtime_id:       s.runtime_id
		epoch:            s.world_binding().epoch
		numeric_id:       numeric_id
		block_runtime_id: block_runtime_id
		count:            count
	})
	return true
}
