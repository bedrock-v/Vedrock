module session

import protocol
import protocol.types
import server.entity
import server.event
import server.world

// WorldEntityHost adapts one WorldRuntime to entity.Host, scoping every
// query and broadcast to sessions and blocks in this world only, the same
// isolation WorldLiquidHost and broadcast_world already give block writes
// and liquid spread. Its methods run on the owning world actor, since
// entity.Manager.tick() dispatches into Behaviour.tick() which calls back
// into these, so returning a live &Entity here is safe. Code outside the
// actor has to snapshot instead (see world_call usage in combat.v).
struct WorldEntityHost {
mut:
	wr &WorldRuntime
}

fn (mut h WorldEntityHost) broadcast(p protocol.Packet) {
	h.wr.broadcast_world(p)
}

fn (mut h WorldEntityHost) broadcast_near(x f32, y f32, z f32, radius f32, p protocol.Packet) {
	r2 := radius * radius
	for mut entry in h.wr.players.values() {
		pos := entry.session.current_position()
		dx := pos.x - x
		dy := pos.y - y
		dz := pos.z - z
		if dx * dx + dy * dy + dz * dz <= r2 {
			entry.session.deliver(p)
		}
	}
}

// allocate_runtime_id is shared across every world through Hub, so entity
// and player runtime ids never collide. The one piece that stays global on
// purpose, matching entity.Host's original contract.
fn (mut h WorldEntityHost) allocate_runtime_id() u64 {
	return h.wr.hub.allocate_runtime_id()
}

fn (mut h WorldEntityHost) get_block(x int, y int, z int) int {
	if id := h.wr.world.block_override(x, y, z) {
		return id
	}
	gen := h.wr.world.make_generator(h.wr.hub.build_generator(h.wr.world))
	return gen.block_at(x, y, z)
}

fn (mut h WorldEntityHost) collision_boxes(x int, y int, z int) []world.AABB {
	id := h.get_block(x, y, z)
	if id == world.air.network_id {
		return []world.AABB{}
	}
	if isnil(h.wr.hub.palette) {
		return world.absolute_boxes(world.solid_model(), x, y, z)
	}
	return world.absolute_boxes_with_neighbors(h.wr.hub.palette.model(id), h.neighbor_models(x, y,
		z), x, y, z)
}

fn (mut h WorldEntityHost) neighbor_models(x int, y int, z int) map[int]world.BlockModel {
	mut out := map[int]world.BlockModel{}
	out[2] = h.wr.hub.palette.model(h.get_block(x, y, z - 1))
	out[3] = h.wr.hub.palette.model(h.get_block(x, y, z + 1))
	out[4] = h.wr.hub.palette.model(h.get_block(x - 1, y, z))
	out[5] = h.wr.hub.palette.model(h.get_block(x + 1, y, z))
	return out
}

fn (mut h WorldEntityHost) entity_position(runtime_id u64) ?types.Vector3 {
	for mut entry in h.wr.players.values() {
		if entry.session.runtime_id == runtime_id {
			return entry.session.current_position()
		}
	}
	e := h.wr.entities.by_runtime_id(runtime_id) or { return none }
	return e.pos
}

fn (mut h WorldEntityHost) entity_hit_test(pos types.Vector3, exclude_runtime_id u64) ?u64 {
	if rid := h.wr.entities.hit_test(pos, exclude_runtime_id) {
		return rid
	}
	for mut entry in h.wr.players.values() {
		if entry.session.runtime_id == exclude_runtime_id {
			continue
		}
		tp := entry.session.current_position()
		feet_y := tp.y - player_eye_height
		if pos.x >= tp.x - player_half_width && pos.x <= tp.x + player_half_width
			&& pos.z >= tp.z - player_half_width && pos.z <= tp.z + player_half_width
			&& pos.y >= feet_y && pos.y <= feet_y + player_height {
			return entry.session.runtime_id
		}
	}
	return none
}

// damage_entity applies mob/projectile-originated damage to a player or
// another entity on the owning world runtime.
fn (mut h WorldEntityHost) damage_entity(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3) {
	for mut entry in h.wr.players.values() {
		if entry.session.runtime_id == runtime_id {
			entry.session.apply_knockback(knockback_from, knockback_horizontal, knockback_vertical)
			entry.session.apply_hurt(mut h.wr, amount, source_name)
			return
		}
	}
	h.wr.entities.damage(runtime_id, amount, true, mut h, source_runtime_id)
}

fn (mut h WorldEntityHost) nearest_player(pos types.Vector3, radius f32) ?u64 {
	mut best_rid := u64(0)
	mut best_dist_sq := radius * radius
	mut found := false
	for mut entry in h.wr.players.values() {
		tp := entry.session.current_position()
		dx := tp.x - pos.x
		dy := tp.y - pos.y
		dz := tp.z - pos.z
		dist_sq := dx * dx + dy * dy + dz * dz
		if dist_sq <= best_dist_sq {
			best_rid = entry.session.runtime_id
			best_dist_sq = dist_sq
			found = true
		}
	}
	if !found {
		return none
	}
	return best_rid
}

// notify_entity_despawn dispatches entity_despawn on this world's event bus.
fn (mut h WorldEntityHost) notify_entity_despawn(identifier string, x f32, y f32, z f32) {
	mut ctx := event.new_context(event.EntityDespawnData{
		identifier: identifier
		x:          x
		y:          y
		z:          z
	})
	h.wr.events.entity_despawn(mut ctx)
}

// SpawnEntityTask resolves and, unless the owning world's entity_spawn
// event is cancelled, spawns a registered entity type in one actor call.
struct SpawnEntityTask {
	behaviour entity.Behaviour
	x         f32
	y         f32
	z         f32
	result    chan bool = chan bool{cap: 1}
}

fn (t SpawnEntityTask) run(mut tx WorldTx) {
	mut spawned := false
	defer {
		t.result <- spawned
	}
	mut ctx := event.new_context(event.EntitySpawnData{
		identifier: t.behaviour.identifier()
		x:          t.x
		y:          t.y
		z:          t.z
	})
	tx.wr.events.entity_spawn(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	tx.wr.entities.spawn(t.behaviour, types.Vector3{t.x, t.y, t.z})
	spawned = true
}
