module session

import math
import bedrock_v.protocol.types
import server.entity
import server.event
import server.world
import server.worldrt

// los_sample_step controls the distance between line of sight samples.
// Smaller values improve accuracy but require more collision checks.
const los_sample_step = f32(0.5)

// WorldEntityHost adapts one worldrt.WorldRuntime to entity.Host, scoping every
// query and broadcast to sessions and blocks in this world only, the same
// isolation WorldLiquidHost already gives block writes and liquid spread.
// Its methods run on the owning world actor, since
// entity.Manager.tick() dispatches into Behaviour.tick() which calls back
// into these, so returning a live &Entity here is safe. Code outside the
// actor has to snapshot instead (see worldrt.world_call usage in combat.v).
struct WorldEntityHost {
mut:
	wr &worldrt.WorldRuntime
}

// tx is how a host method reaches world mutation. entity.Host methods run
// only while the entity manager is ticking, which happens on the world actor,
// and entity can't name WorldTx without an import cycle. That's why the transaction
// is rebuilt here instead of being passed in.
fn (mut h WorldEntityHost) tx() worldrt.WorldTx {
	return worldrt.WorldTx{
		wr: h.wr
	}
}

// new_world_entity_host builds the entity manager's host for wr. The runtime
// takes it as a function because the host needs the runtime, which does not
// exist yet when its config is written.
fn new_world_entity_host(wr &worldrt.WorldRuntime) entity.Host {
	return WorldEntityHost{
		wr: unsafe { wr }
	}
}

fn (mut h WorldEntityHost) viewers() []entity.Viewer {
	return h.wr.viewers()
}

// viewers_near is everyone close enough to a point to be shown something
// happening there. It is the only distance filter in the viewer path; the
// world wide one doesn't have it.
fn (mut h WorldEntityHost) viewers_near(x f32, y f32, z f32, radius f32) []entity.Viewer {
	r2 := radius * radius
	mut out := []entity.Viewer{}
	for mut a in h.wr.entities.player_actors() {
		pos := a.current_position()
		dx := pos.x - x
		dy := pos.y - y
		dz := pos.z - z
		if dx * dx + dy * dy + dz * dz > r2 {
			continue
		}
		if mut a is NetworkSession {
			out << a
		}
	}
	return out
}

// allocate_runtime_id is shared across every world through Hub, so entity
// and player runtime ids never collide. The one piece that stays global on
// purpose, matching entity.Host's original contract.
fn (mut h WorldEntityHost) allocate_runtime_id() u64 {
	return h.wr.services.allocate_runtime_id()
}

fn (mut h WorldEntityHost) get_block(x int, y int, z int) int {
	if id := h.wr.world.block_override(x, y, z) {
		return id
	}
	gen := h.wr.world.make_generator(h.wr.generators.build_generator(h.wr.world))
	return gen.block_at(x, y, z)
}

fn (mut h WorldEntityHost) collision_boxes(x int, y int, z int) []world.AABB {
	id := h.get_block(x, y, z)
	if id == world.air.network_id {
		return []world.AABB{}
	}
	if isnil(h.wr.services.block_palette()) {
		return world.absolute_boxes(world.solid_model(), x, y, z)
	}
	return world.absolute_boxes_with_neighbors(h.wr.services.block_palette().model(id), h.neighbor_models(x, y,
		z), x, y, z)
}

fn (mut h WorldEntityHost) neighbor_models(x int, y int, z int) map[int]world.BlockModel {
	mut out := map[int]world.BlockModel{}
	out[2] = h.wr.services.block_palette().model(h.get_block(x, y, z - 1))
	out[3] = h.wr.services.block_palette().model(h.get_block(x, y, z + 1))
	out[4] = h.wr.services.block_palette().model(h.get_block(x - 1, y, z))
	out[5] = h.wr.services.block_palette().model(h.get_block(x + 1, y, z))
	return out
}

// entity_position is the unified lookup. Any registered actor, mob or
// player, resolved through Manager's storage. current_position() is one of
// entity.Actor's own methods, so no narrowing is needed here at all.
fn (mut h WorldEntityHost) entity_position(runtime_id u64) ?types.Vector3 {
	a := h.wr.entities.actor_by_runtime_id(runtime_id) or { return none }
	return a.current_position()
}

// entity_hit_test checks every registered actor using its own feet position
// and dimensions. Players and non-player entities share the same path
// through the Actor interface.
fn (mut h WorldEntityHost) entity_hit_test(pos types.Vector3, exclude_runtime_ids []u64) ?u64 {
	for a in h.wr.entities.all_actors() {
		if a.runtime_id() in exclude_runtime_ids || a.is_dead() {
			continue
		}
		feet := a.feet_position()
		d := a.dimensions()
		half_width := d.width / 2
		if pos.x >= feet.x - half_width && pos.x <= feet.x + half_width
			&& pos.z >= feet.z - half_width && pos.z <= feet.z + half_width && pos.y >= feet.y
			&& pos.y <= feet.y + d.height {
			return a.runtime_id()
		}
	}
	return none
}

fn damage_actor(mut tx worldrt.WorldTx, runtime_id u64, amount f32, source DamageSource, source_runtime_id u64, knockback_from types.Vector3, knockback_force f32, knockback_height f32) {
	mut a := tx.wr.entities.actor_by_runtime_id(runtime_id) or { return }
	if mut a is NetworkSession {
		a.apply_knockback(knockback_from, knockback_force, knockback_height)
		a.apply_hurt(mut tx, amount, source)
		return
	}
	mut host := WorldEntityHost{
		wr: tx.wr
	}
	tx.wr.entities.damage(runtime_id, amount, true, mut host, source_runtime_id)
}

// damage_entity applies mob/projectile-originated damage to a player or
// another entity on the owning world runtime. source_name identifies the
// attacker and is wrapped here because the entity package can't construct
// session damage sources without creating an import cycle.
//
// Melee damage uses PlayerAttackTask and doesn't pass through this path.
fn (mut h WorldEntityHost) damage_entity(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3) {
	mut tx := h.tx()
	damage_actor(mut tx, runtime_id, amount, ProjectileDamageSource{
		attacker_name: source_name
	}, source_runtime_id, knockback_from, knockback_horizontal, knockback_vertical)
}

fn (mut h WorldEntityHost) mob_attack(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3) {
	mut tx := h.tx()
	damage_actor(mut tx, runtime_id, amount, MobAttackDamageSource{
		attacker_name: source_name
	}, source_runtime_id, knockback_from, knockback_horizontal, knockback_vertical)
}

fn (mut h WorldEntityHost) has_line_of_sight(from types.Vector3, to types.Vector3) bool {
	dx := to.x - from.x
	dy := to.y - from.y
	dz := to.z - from.z
	dist := math.sqrtf(dx * dx + dy * dy + dz * dz)
	if dist < 0.0001 {
		return true
	}
	steps := int(dist / los_sample_step) + 1
	for i := 1; i < steps; i++ {
		t := f32(i) / f32(steps)
		x := int(math.floor(from.x + dx * t))
		y := int(math.floor(from.y + dy * t))
		z := int(math.floor(from.z + dz * t))
		if h.collision_boxes(x, y, z).len > 0 {
			return false
		}
	}
	return true
}

// nearest_player scans only registered player actors.
fn (mut h WorldEntityHost) nearest_player(pos types.Vector3, radius f32) ?u64 {
	mut best_rid := u64(0)
	mut best_dist_sq := radius * radius
	mut found := false
	for a in h.wr.entities.player_actors() {
		tp := a.current_position()
		dx := tp.x - pos.x
		dy := tp.y - pos.y
		dz := tp.z - pos.z
		dist_sq := dx * dx + dy * dy + dz * dz
		if dist_sq <= best_dist_sq {
			best_rid = a.runtime_id()
			best_dist_sq = dist_sq
			found = true
		}
	}
	if !found {
		return none
	}
	return best_rid
}

// notify_entity_despawn dispatches entity_despawn on this world's handler.
fn (mut h WorldEntityHost) notify_entity_despawn(identifier string, x f32, y f32, z f32) {
	mut ctx := event.new_context(event.EntityDespawnData{
		identifier: identifier
		x:          x
		y:          y
		z:          z
	})
	h.wr.handler.on_entity_despawn(mut ctx)
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

fn (t SpawnEntityTask) name() string {
	return 'SpawnEntityTask'
}

fn (t SpawnEntityTask) run(mut tx worldrt.WorldTx) {
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
	tx.wr.handler.on_entity_spawn(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	tx.wr.entities.spawn(t.behaviour, types.Vector3{t.x, t.y, t.z})
	spawned = true
}
