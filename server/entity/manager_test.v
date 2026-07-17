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
