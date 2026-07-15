module entity

import protocol
import protocol.types
import server.world

// FakeHost stands in for Hub: it hands out ids, counts broadcasts and backs a
// small in-memory block grid so collision can be tested without a real world.
// Any coordinate not in solids reads as air.
struct FakeHost {
mut:
	next       u64 = 1
	broadcasts int
	near       int
	solids     map[string]int
}

fn block_key(x int, y int, z int) string {
	return '${x},${y},${z}'
}

fn (mut h FakeHost) set_solid(x int, y int, z int) {
	h.solids[block_key(x, y, z)] = 1
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
	if _ := h.solids[block_key(x, y, z)] {
		return 1
	}
	return world.air.network_id
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

fn test_spawn_uses_near_broadcast() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 10, 0})
	assert host.near == 1 // AddActor routed through broadcast_near
}

fn test_projectile_despawns_after_max_age() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&ProjectileBehaviour{ network_id: 'minecraft:snowball', max_age: 5 },
		types.Vector3{0, 10, 0})
	e.no_gravity = true // isolate the age check from the ground check
	for _ in 0 .. 6 {
		m.tick()
	}
	assert m.count() == 0
}
