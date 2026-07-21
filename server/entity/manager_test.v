module entity

import time
import protocol
import protocol.types
import server.world
import server.effect

// FakeHost stands in for Hub: it hands out ids, counts broadcasts and backs a
// small in-memory block grid so collision can be tested without a real world.
// Any coordinate not in solids reads as air.
struct FakeHost {
mut:
	next                   u64 = 1
	broadcasts             int
	near                   int
	blocks                 map[string]int
	boxes                  map[string][]world.AABB
	positions              map[u64]types.Vector3
	hit_target             ?u64
	damage_calls           int
	last_damage_runtime_id u64
	last_damage_amount     f32
	// players is the settable pool nearest_player searches: keyed by runtime
	// id, distinct from the generic entity positions map above.
	players               map[u64]types.Vector3
	despawn_notify_calls   int
	last_despawn_id        string
	pickup_result bool
	pickup_calls  int
}

fn block_key(x int, y int, z int) string {
	return '${x},${y},${z}'
}

fn (mut h FakeHost) set_solid(x int, y int, z int) {
	key := block_key(x, y, z)
	h.blocks[key] = 1
	h.boxes[key] = world.absolute_boxes(world.solid_model(), x, y, z)
}

fn (mut h FakeHost) set_empty_non_air(x int, y int, z int) {
	key := block_key(x, y, z)
	h.blocks[key] = 42
	h.boxes[key] = []world.AABB{}
}

fn (mut h FakeHost) broadcast(p protocol.Packet) {
	h.broadcasts++
}

fn (mut h FakeHost) broadcast_near(x f32, y f32, z f32, radius f32, p protocol.Packet) {
	h.near++
}

fn (mut h FakeHost) allocate_runtime_id() u64 {
	id := h.next
	h.next++
	return id
}

fn (mut h FakeHost) get_block(x int, y int, z int) int {
	return h.blocks[block_key(x, y, z)] or { world.air.network_id }
}

fn (mut h FakeHost) collision_boxes(x int, y int, z int) []world.AABB {
	return h.boxes[block_key(x, y, z)] or { []world.AABB{} }
}

fn (mut h FakeHost) entity_position(runtime_id u64) ?types.Vector3 {
	return h.positions[runtime_id] or { none }
}

fn (mut h FakeHost) entity_hit_test(pos types.Vector3, exclude_runtime_id u64) ?u64 {
	return h.hit_target
}

fn (mut h FakeHost) damage_entity(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3) {
	h.damage_calls++
	h.last_damage_runtime_id = runtime_id
	h.last_damage_amount = amount
}

fn (mut h FakeHost) notify_entity_despawn(identifier string, x f32, y f32, z f32) {
	h.despawn_notify_calls++
	h.last_despawn_id = identifier
}

fn (mut h FakeHost) nearest_player(pos types.Vector3, radius f32) ?u64 {
	radius_sq := radius * radius
	mut best_rid := u64(0)
	mut best_dist_sq := radius_sq
	mut found := false
	for rid, p in h.players {
		dx := p.x - pos.x
		dy := p.y - pos.y
		dz := p.z - pos.z
		dist_sq := dx * dx + dy * dy + dz * dz
		if dist_sq <= best_dist_sq {
			best_rid = rid
			best_dist_sq = dist_sq
			found = true
		}
	}
	if !found {
		return none
	}
	return best_rid
}

fn (mut h FakeHost) pickup_item(item_runtime_id u64, stack types.ItemStack, pos types.Vector3) bool {
	h.pickup_calls++
	return h.pickup_result
}

fn test_spawn_registers_and_broadcasts() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 10, 0})
	assert m.count() == 1
	assert e.identifier == 'minecraft:pig'
	assert e.runtime_id == 1
	assert host.near == 1 // AddActor routed through broadcast_near
	assert host.broadcasts == 0
}

fn test_despawn_removes_and_broadcasts() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:cow' }, types.Vector3{0, 0, 0})
	m.despawn(e.runtime_id)
	assert m.count() == 0
	assert host.near == 1 // AddActor via broadcast_near
	assert host.broadcasts == 1 // RemoveActor via broadcast
}

fn test_gravity_pulls_entity_down() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 10, 0})
	e.floor_y = 0 // let it fall
	m.tick()
	assert e.pos.y < 10
	assert !e.on_ground
}

fn test_entity_rests_on_floor() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 5, 0})
	// floor_y defaults to spawn y, so it should not sink.
	m.tick()
	assert e.pos.y == 5
	assert e.on_ground
}

fn test_entity_lands_on_solid_block() {
	mut host := &FakeHost{}
	host.set_solid(0, 4, 0) // block top at y=5
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0.5, 10, 0.5})
	e.floor_y = -64 // let real block detection do the work, not the fallback
	for _ in 0 .. 40 {
		m.tick()
	}
	assert e.on_ground
	assert e.pos.y == 5.0 // feet snapped to block top
}

fn test_entity_does_not_pass_through_wall() {
	mut host := &FakeHost{}
	host.set_solid(1, 5, 0) // wall east of the entity
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0.5, 5, 0.5})
	e.floor_y = 5
	e.no_gravity = true
	e.set_velocity(types.Vector3{0.5, 0, 0}) // push toward the wall
	for _ in 0 .. 10 {
		e.set_velocity(types.Vector3{0.5, 0, 0})
		m.tick()
	}
	assert e.pos.x < 1.0 // blocked before entering the wall block at x=1
}

fn test_entity_ignores_non_air_blocks_without_collision_boxes() {
	mut host := &FakeHost{}
	host.set_empty_non_air(1, 5, 0)
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0.5, 5, 0.5})
	e.floor_y = 5
	e.no_gravity = true
	e.set_velocity(types.Vector3{0.5, 0, 0})
	for _ in 0 .. 4 {
		e.set_velocity(types.Vector3{0.5, 0, 0})
		m.tick()
	}
	assert e.pos.x > 1.0
}

fn test_spawn_uses_near_broadcast() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 10, 0})
	assert host.near == 1 // AddActor routed through broadcast_near
}

fn test_projectile_despawns_after_max_age() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e :=
		m.spawn(&ProjectileBehaviour{ network_id: 'minecraft:snowball', max_age: 5 }, types.Vector3{0, 10, 0})
	e.no_gravity = true // isolate the age check from the ground check
	for _ in 0 .. 6 {
		m.tick()
	}
	assert m.count() == 0
}

fn test_by_runtime_id_finds_live_entity_and_none_after_despawn() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 10, 0})
	found := m.by_runtime_id(e.runtime_id) or { panic('expected the entity to be found') }
	assert found.runtime_id == e.runtime_id
	m.despawn(e.runtime_id)
	assert m.by_runtime_id(e.runtime_id) == none
}

fn test_hostile_behaviour_chases_target_set_by_on_hurt() {
	mut host := &FakeHost{}
	host.positions[99] = types.Vector3{10, 5, 0}
	mut m := new_manager(host)
	mut e := m.spawn(&HostileBehaviour{ network_id: 'minecraft:zombie' }, types.Vector3{0, 5, 0})
	e.floor_y = 5
	e.no_gravity = true
	// Before being hurt, a HostileBehaviour has no target and shouldn't
	// suddenly move toward (10, 5, 0) on its own within a single tick.
	m.tick()
	assert e.pos.x < 1.0

	e.hurt(mut host, 5, true, 99)
	assert e.health == 15
	m.tick()
	assert e.velocity.x > 0 // now moving toward the attacker at x=10
}

fn test_hurt_behaviour_not_dispatched_to_passive_mobs() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 5, 0})
	e.hurt(mut host, 5, true, 99)
	assert e.health == 15 // damage still applies, just no HurtBehaviour reaction
}

fn test_projectile_hits_entity_via_entity_hit_test() {
	mut host := &FakeHost{}
	host.hit_target = u64(42)
	mut m := new_manager(host)
	mut e := m.spawn(&ProjectileBehaviour{
		network_id: 'minecraft:snowball'
		damage:     3
	}, types.Vector3{0, 10, 0})
	e.no_gravity = true
	e.age = 2 // past the spawn tick guard
	m.tick()
	assert host.damage_calls == 1
	assert host.last_damage_runtime_id == 42
	assert host.last_damage_amount == 3
	assert m.count() == 0 // the projectile kills itself on hit
}

fn test_entity_takes_poison_damage_on_tick() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 5, 0})
	e.add_effect(mut host, effect.new(effect.poison, 1, 5 * time.second))
	for _ in 0 .. 51 {
		m.tick()
	}
	assert e.health < 20
}

fn test_entity_heals_from_instant_health_effect() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 5, 0})
	e.health = 10
	e.add_effect(mut host, effect.new_instant(effect.instant_health, 1))
	assert e.health > 10
}

fn test_projectile_survives_block_collision_and_freezes() {
	mut host := &FakeHost{}
	host.set_solid(1, 5, 0) // wall east of the spawn point
	mut m := new_manager(host)
	mut e := m.spawn(&ProjectileBehaviour{
		network_id:              'minecraft:arrow'
		survive_block_collision: true
	}, types.Vector3{0.5, 5, 0.5})
	e.floor_y = 5
	e.no_gravity = true
	e.age = 2 // past the spawn tick guard
	e.set_velocity(types.Vector3{0.5, 0, 0})
	m.tick() // hits the wall this tick, cancels velocity, flags hit_block
	m.tick() // behaviour sees hit_block and freezes
	assert m.count() == 1 // stuck, not despawned
	stuck_pos := e.pos
	m.tick()
	m.tick()
	assert e.pos.x == stuck_pos.x // frozen in place
	assert e.velocity.x == 0
	assert m.count() == 1
}

fn test_projectile_without_survive_despawns_on_wall_hit() {
	mut host := &FakeHost{}
	host.set_solid(1, 5, 0) // wall east of the spawn point
	mut m := new_manager(host)
	mut e := m.spawn(&ProjectileBehaviour{
		network_id:              'minecraft:snowball'
		survive_block_collision: false
	}, types.Vector3{0.5, 5, 0.5})
	e.floor_y = 5
	e.no_gravity = true
	e.age = 2
	e.set_velocity(types.Vector3{0.5, 0, 0})
	m.tick() // hits the wall this tick, cancels velocity, flags hit_block
	m.tick() // behaviour sees hit_block and despawns
	// previously only landing on top (on_ground) despawned a projectile.
	assert m.count() == 0
}

fn test_projectile_gravity_is_configurable_per_instance() {
	mut light_host := &FakeHost{}
	mut light_m := new_manager(light_host)
	mut light := light_m.spawn(&ProjectileBehaviour{
		network_id:    'minecraft:snowball'
		gravity_accel: 0.03
	}, types.Vector3{0, 100, 0})
	light.floor_y = -1000
	light.age = 2

	mut heavy_host := &FakeHost{}
	mut heavy_m := new_manager(heavy_host)
	mut heavy := heavy_m.spawn(&ProjectileBehaviour{
		network_id:    'minecraft:arrow'
		gravity_accel: 0.05
	}, types.Vector3{0, 100, 0})
	heavy.floor_y = -1000
	heavy.age = 2

	for _ in 0 .. 20 {
		light_m.tick()
		heavy_m.tick()
	}
	assert heavy.pos.y < light.pos.y // heavier gravity falls faster
}

fn test_hostile_behaviour_proactively_targets_nearby_player_without_being_hurt() {
	mut host := &FakeHost{}
	// players drives the nearest_player scan; positions drives the
	// existing entity_position lookup the chase step already uses.
	// A real Hub resolves both from the same live session, FakeHost keeps
	// them as two settable maps.
	host.players[99] = types.Vector3{10, 5, 0}
	host.positions[99] = types.Vector3{10, 5, 0}
	mut m := new_manager(host)
	mut e := m.spawn(&HostileBehaviour{
		network_id:       'minecraft:zombie'
		detection_radius: 16.0
	}, types.Vector3{0, 5, 0})
	e.floor_y = 5
	e.no_gravity = true
	m.tick()
	m.tick() // target acquired last tick; this tick moves toward it
	assert e.velocity.x > 0
}

fn test_item_entity_spawns_as_item_actor() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	stack := types.ItemStack{
		id:    5
		count: 3
	}
	e := m.spawn_item(stack, types.Vector3{0, 10, 0}, types.Vector3{}, 10)
	assert m.count() == 1
	assert e.identifier == 'minecraft:item'
	assert e.pickup_delay == 10
	got := e.item or { panic('expected the item stack to be set') }
	assert got.id == 5
	assert got.count == 3
	assert host.near == 1
}

fn test_item_entity_waits_out_pickup_delay_then_is_collected() {
	mut host := &FakeHost{
		pickup_result: true
	}
	mut m := new_manager(host)
	mut e := m.spawn_item(types.ItemStack{ id: 5, count: 1 }, types.Vector3{0, 5, 0},
		types.Vector3{}, 2)
	e.floor_y = 5
	m.tick()
	assert host.pickup_calls == 0
	m.tick()
	assert host.pickup_calls == 0
	assert m.count() == 1
	m.tick()
	assert host.pickup_calls == 1
	assert m.count() == 0
}

fn test_item_entity_stays_when_pickup_refused() {
	mut host := &FakeHost{
		pickup_result: false
	}
	mut m := new_manager(host)
	mut e := m.spawn_item(types.ItemStack{ id: 5, count: 1 }, types.Vector3{0, 5, 0},
		types.Vector3{}, 0)
	e.floor_y = 5
	m.tick()
	assert host.pickup_calls == 1
	assert m.count() == 1
}

fn test_item_entity_despawns_after_lifetime() {
	mut host := &FakeHost{
		pickup_result: false
	}
	mut m := new_manager(host)
	mut e := m.spawn_item(types.ItemStack{ id: 5, count: 1 }, types.Vector3{0, 5, 0},
		types.Vector3{}, 0)
	e.floor_y = 5
	e.age = item_despawn_ticks
	m.tick()
	assert m.count() == 0
}

fn test_hostile_behaviour_gives_up_target_out_of_range() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&HostileBehaviour{
		network_id:       'minecraft:zombie'
		detection_radius: 10.0
	}, types.Vector3{0, 5, 0})
	e.floor_y = 5
	e.no_gravity = true
	e.hurt(mut host, 1, true, 99)
	host.positions[99] = types.Vector3{9, 5, 0} // within detection_radius * 1.5
	m.tick()
	assert e.velocity.x > 0 // still chasing

	host.positions[99] = types.Vector3{100, 5, 0} // far past the giveup range
	e.set_velocity(types.Vector3{})
	m.tick()
	assert e.velocity.x == 0 // gave up, back to wandering
}
