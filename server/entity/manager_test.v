module entity

import os
import time
import protocol

import protocol.types
import server.world
import server.effect
import protocol.current as proto

// FakeHost stands in for Hub: it hands out ids, counts broadcasts and backs a
// small in-memory block grid so collision can be tested without a real world.
// Any coordinate not in solids reads as air.
struct FakeHost {
mut:
	next                          u64 = 1
	broadcasts                    int
	near                          int
	blocks                        map[string]int
	boxes                         map[string][]world.AABB
	positions                     map[u64]types.Vector3
	hit_target                    ?u64
	last_hit_test_excluded        []u64
	damage_calls                  int
	last_damage_runtime_id        u64
	last_damage_amount            f32
	last_damage_source_runtime_id u64
	mob_attack_calls              int
	last_mob_attack_runtime_id    u64
	last_mob_attack_amount        f32
	visible                       bool = true
	// players is the settable pool nearest_player searches: keyed by runtime
	// id, distinct from the generic entity positions map above.
	players              map[u64]types.Vector3
	despawn_notify_calls int
	last_despawn_id      string
	// dropped_items records every spawn_dropped_item call this host receives.
	dropped_items []DroppedItemCall
	// collect_response is how many units collect_item pretends to add.
	collect_response        int
	collect_calls           int
	last_collect_runtime_id u64
	last_collect_stack      types.ItemStack
	take_notify_calls       int
	last_take_item_rid      u64
	last_take_taker_rid     u64
}

struct DroppedItemCall {
	item_name string
	count     int
	pos       types.Vector3
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

fn (mut h FakeHost) set_slab(x int, y int, z int) {
	key := block_key(x, y, z)
	h.blocks[key] = 1
	h.boxes[key] = world.absolute_boxes(world.slab_model(false, false), x, y, z)
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

fn (mut h FakeHost) entity_hit_test(pos types.Vector3, exclude_runtime_ids []u64) ?u64 {
	h.last_hit_test_excluded = exclude_runtime_ids
	if target := h.hit_target {
		if target in exclude_runtime_ids {
			return none
		}
	}
	return h.hit_target
}

fn (mut h FakeHost) damage_entity(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3) {
	h.damage_calls++
	h.last_damage_runtime_id = runtime_id
	h.last_damage_amount = amount
	h.last_damage_source_runtime_id = source_runtime_id
}

fn (mut h FakeHost) mob_attack(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3) {
	h.mob_attack_calls++
	h.last_mob_attack_runtime_id = runtime_id
	h.last_mob_attack_amount = amount
}

fn (mut h FakeHost) has_line_of_sight(from types.Vector3, to types.Vector3) bool {
	return h.visible
}

fn (mut h FakeHost) notify_entity_despawn(identifier string, x f32, y f32, z f32) {
	h.despawn_notify_calls++
	h.last_despawn_id = identifier
}

fn (mut h FakeHost) spawn_dropped_item(item_name string, count int, pos types.Vector3) {
	h.dropped_items << DroppedItemCall{
		item_name: item_name
		count:     count
		pos:       pos
	}
}

fn (mut h FakeHost) collect_item(runtime_id u64, stack types.ItemStack) int {
	h.collect_calls++
	h.last_collect_runtime_id = runtime_id
	h.last_collect_stack = stack
	return h.collect_response
}

fn (mut h FakeHost) notify_item_taken(item_runtime_id u64, taker_runtime_id u64) {
	h.take_notify_calls++
	h.last_take_item_rid = item_runtime_id
	h.last_take_taker_rid = taker_runtime_id
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

struct FakeActor {
	rid u64
	pos types.Vector3
}

fn (a &FakeActor) runtime_id() u64 {
	return a.rid
}

fn (a &FakeActor) current_position() types.Vector3 {
	return a.pos
}

fn (a &FakeActor) feet_position() types.Vector3 {
	return a.pos
}

fn (a &FakeActor) dimensions() Dimensions {
	return Dimensions{}
}

fn (a &FakeActor) is_dead() bool {
	return false
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

fn test_entity_steps_up_slab_height_ledge() {
	mut host := &FakeHost{}
	host.set_slab(2, 5, 0) // top surface at y=5.5 - a 0.5 block step up
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0.5, 5, 0.5})
	e.floor_y = 5
	e.no_gravity = true
	for _ in 0 .. 20 {
		e.set_velocity(types.Vector3{0.3, 0, 0})
		m.tick()
	}
	assert e.pos.x > 2.0 // stepped up and continued past the slab, not stuck at its vertical face
	assert e.pos.y >= 5.5 // settled on top of the stepped-up surface
}

fn test_entity_without_collision_passes_through_wall() {
	mut host := &FakeHost{}
	host.set_solid(1, 5, 0) // wall east of the entity, would normally block it
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{
		network_id: 'minecraft:pig'
		dimensions: Dimensions{
			has_collision: false
		}
	}, types.Vector3{0.5, 5, 0.5})
	e.floor_y = 5
	e.no_gravity = true
	for _ in 0 .. 10 {
		e.set_velocity(types.Vector3{0.5, 0, 0})
		m.tick()
	}
	assert e.pos.x > 1.0 // has_collision: false skips block collision entirely
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

fn test_no_fall_damage_within_safe_distance() {
	mut host := &FakeHost{}
	host.set_solid(0, 8, 0) // block top at y=9, just below the spawn point
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0.5, 10, 0.5})
	e.floor_y = -1000
	for _ in 0 .. 30 {
		m.tick()
		if e.on_ground {
			break
		}
	}
	assert e.on_ground
	assert e.health == 20.0
}

fn test_projectile_takes_no_fall_damage() {
	mut host := &FakeHost{}
	host.set_solid(0, 0, 0) // block top at y=1
	mut m := new_manager(host)
	mut e :=
		m.spawn(&ProjectileBehaviour{ network_id: 'minecraft:arrow', max_age: 1000 }, types.Vector3{0.5, 10, 0.5})
	for _ in 0 .. 60 {
		m.tick()
		if e.on_ground || m.count() == 0 {
			break
		}
	}
	assert e.health == 20.0
}

fn test_spawn_uses_near_broadcast() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 10, 0})
	assert host.near == 1 // AddActor routed through broadcast_near
}

fn test_mob_never_despawns_when_nobody_is_registered_in_the_world() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{
		network_id:     'minecraft:pig'
		despawn_policy: natural_mob_despawn_policy
	}, types.Vector3{0, 5, 0})
	e.floor_y = 5
	for _ in 0 .. 20 {
		m.tick()
	}
	assert m.count() == 1 // nobody online at all, the distance policy must not apply
}

fn test_mob_never_despawns_near_registered_player() {
	mut host := &FakeHost{}
	host.players[999] = types.Vector3{1, 5, 0} // well within despawn_never_radius
	mut m := new_manager(host)
	m.register_player_actor(&FakeActor{ rid: 999, pos: types.Vector3{1, 5, 0} }, 999, 0)
	mut e := m.spawn(&PassiveBehaviour{
		network_id:     'minecraft:pig'
		despawn_policy: natural_mob_despawn_policy
	}, types.Vector3{0, 5, 0})
	e.floor_y = 5
	for _ in 0 .. 20 {
		m.tick()
	}
	assert m.count() == 1
}

fn test_mob_despawns_when_far_from_only_registered_player() {
	mut host := &FakeHost{}
	host.players[999] = types.Vector3{5000, 5, 0}
	mut m := new_manager(host)
	m.register_player_actor(&FakeActor{ rid: 999, pos: types.Vector3{5000, 5, 0} }, 999, 0)
	mut e := m.spawn(&PassiveBehaviour{
		network_id:     'minecraft:pig'
		despawn_policy: natural_mob_despawn_policy
	}, types.Vector3{0, 5, 0})
	e.floor_y = 5
	m.tick()
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

fn test_hostile_behaviour_melee_attacks_once_in_range_and_stops_moving() {
	mut host := &FakeHost{}
	host.positions[99] = types.Vector3{1.5, 5, 0} // within mob_attack_range (2.0) of the mob
	mut m := new_manager(host)
	mut e := m.spawn(&HostileBehaviour{
		network_id:    'minecraft:zombie'
		attack_damage: 4.0
	}, types.Vector3{0, 5, 0})
	e.floor_y = 5
	e.no_gravity = true
	e.hurt(mut host, 1, false, 99)

	m.tick()
	assert e.velocity.x == 0 // in range, stands and attacks instead of closing the last distance
	assert host.mob_attack_calls == 1
	assert host.last_mob_attack_runtime_id == 99
	assert host.last_mob_attack_amount == 4.0

	// Attack cooldown gates the next hit
	m.tick()
	assert host.mob_attack_calls == 1
}

fn test_hostile_behaviour_does_not_acquire_target_without_line_of_sight() {
	mut host := &FakeHost{}
	host.players[99] = types.Vector3{5, 5, 0}
	host.visible = false
	mut m := new_manager(host)
	mut e := m.spawn(&HostileBehaviour{ network_id: 'minecraft:zombie' }, types.Vector3{0, 5, 0})
	e.floor_y = 5
	e.no_gravity = true

	for _ in 0 .. detection_scan_interval_ticks + 1 {
		m.tick()
	}
	assert e.velocity.x == 0
}

fn test_hostile_behaviour_gives_up_chase_after_losing_line_of_sight() {
	mut host := &FakeHost{}
	host.positions[99] = types.Vector3{10, 5, 0}
	mut m := new_manager(host)
	mut e := m.spawn(&HostileBehaviour{ network_id: 'minecraft:zombie' }, types.Vector3{0, 5, 0})
	e.floor_y = 5
	e.no_gravity = true
	e.hurt(mut host, 1, false, 99)

	m.tick()
	assert e.velocity.x > 0 // still chasing while visible

	host.visible = false
	for _ in 0 .. los_give_up_ticks + 1 {
		m.tick()
	}
	e.velocity = types.Vector3{}
	m.tick()
	assert e.velocity.x == 0 // gave up
}

fn test_hurt_behaviour_not_dispatched_to_passive_mobs() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 5, 0})
	e.hurt(mut host, 5, true, 99)
	assert e.health == 15 // damage still applies, just no HurtBehaviour reaction
}

fn test_hurt_broadcasts_hurt_event_and_health_attribute_update() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 5, 0})
	host.broadcasts = 0 // spawn's own AddActor goes through broadcast_near
	e.hurt(mut host, 5, true, 99)
	assert host.broadcasts == 2 // ActorEventPacket (hurt) + UpdateAttributesPacket (health)
}

fn test_heal_broadcasts_health_attribute_update() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 5, 0})
	e.health = 10
	host.broadcasts = 0
	e.heal(mut host, 5)
	assert e.health == 15
	assert host.broadcasts == 1
}

fn test_spawn_packet_reports_per_type_dimensions_and_health_attribute() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{
		network_id: 'minecraft:cow'
		dimensions: Dimensions{
			width:  0.9
			height: 1.4
		}
	}, types.Vector3{0, 5, 0})
	e.health = 7

	packet := e.spawn_packet()
	if packet is proto.AddActorPacket {
		assert packet.attributes.len == 1
		assert packet.attributes[0].attribute_name == 'minecraft:health'
		assert packet.attributes[0].current_value == 7
		assert packet.attributes[0].max_value == 20.0

		mut saw_width := false
		mut saw_height := false
		for entry in packet.actor_data {
			if entry.data_item_id == proto.meta_key_width {
				if value := proto.data_item_float(entry.data_item_type) {
					assert value.value == f32(0.9)
					saw_width = true
				}
			}
			if entry.data_item_id == proto.meta_key_height {
				if value := proto.data_item_float(entry.data_item_type) {
					assert value.value == f32(1.4)
					saw_height = true
				}
			}
		}
		assert saw_width
		assert saw_height
	} else {
		assert false, 'expected AddActorPacket for a non-item entity'
	}
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

fn test_projectile_doesnt_hit_owner_within_immunity_window() {
	mut host := &FakeHost{}
	host.hit_target = u64(77) // the "target" entity_hit_test would find is the owner itself
	mut m := new_manager(host)
	mut e := m.spawn(&ProjectileBehaviour{
		network_id:       'minecraft:snowball'
		damage:           3
		owner_runtime_id: 77
	}, types.Vector3{0, 10, 0})
	e.no_gravity = true
	e.age = 2 // inside owner_immunity_ticks (5)
	m.tick()
	assert host.damage_calls == 0
	assert m.count() == 1 // the projectile survives
}

fn test_projectile_can_hit_owner_after_immunity_window() {
	mut host := &FakeHost{}
	host.hit_target = u64(77) // the owner is standing exactly where the projectile now is
	mut m := new_manager(host)
	mut e := m.spawn(&ProjectileBehaviour{
		network_id:       'minecraft:arrow'
		damage:           3
		owner_runtime_id: 77
	}, types.Vector3{0, 10, 0})
	e.no_gravity = true
	e.age = 5 // owner_immunity_ticks has fully elapsed
	m.tick()
	assert host.damage_calls == 1
	assert host.last_damage_runtime_id == 77
	assert m.count() == 0 // the projectile still kills itself on this hit
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

fn (mut h FakeHost) set_floor(x0 int, x1 int, z0 int, z1 int, y int) {
	for x := x0; x <= x1; x++ {
		for z := z0; z <= z1; z++ {
			h.set_solid(x, y, z)
		}
	}
}

fn test_find_path_routes_around_wall_gap() {
	mut host := &FakeHost{}
	host.set_floor(-1, 6, -1, 2, 4)
	host.set_solid(3, 5, -1)
	host.set_solid(3, 5, 0)
	path := find_path(mut host, types.Vector3{0.5, 5, 0.5}, types.Vector3{5.5, 5, 0.5}, Dimensions{}) or {
		panic('expected a path around the gap')
	}
	assert path.len > 0
	mut passed_through_gap := false
	for wp in path {
		if int(wp.x) == 3 && int(wp.z) == 1 {
			passed_through_gap = true
		}
	}
	assert passed_through_gap
	last := path[path.len - 1]
	assert last.x == f32(5.5)
	assert last.z == f32(0.5)
}

fn test_find_path_does_not_cut_diagonal_corners() {
	mut host := &FakeHost{}
	host.set_floor(-2, 3, -2, 3, 4)
	host.set_solid(1, 5, 0)
	host.set_solid(0, 5, 1)
	path := find_path(mut host, types.Vector3{0.5, 5, 0.5}, types.Vector3{1.5, 5, 1.5}, Dimensions{}) or {
		panic('expected a path around the corner')
	}
	assert path.len > 0
	first := path[0]
	assert !(int(first.x) == 1 && int(first.z) == 1)
}

fn test_find_path_returns_none_when_completely_enclosed() {
	mut host := &FakeHost{}
	host.set_solid(0, 4, 0) // floor under the start only
	host.set_solid(1, 5, 0)
	host.set_solid(-1, 5, 0)
	host.set_solid(0, 5, 1)
	host.set_solid(0, 5, -1)
	if _ := find_path(mut host, types.Vector3{0.5, 5, 0.5}, types.Vector3{50.5, 5, 0.5}, Dimensions{}) {
		assert false
	}
}

fn test_hostile_mob_navigates_around_wall_to_reach_target() {
	mut host := &FakeHost{}
	host.set_floor(-1, 6, -1, 2, 4)
	host.set_solid(3, 5, -1)
	host.set_solid(3, 5, 0)
	host.positions[42] = types.Vector3{5.5, 5, 0.5}
	host.players[42] = types.Vector3{5.5, 5, 0.5}
	mut m := new_manager(host)
	mut e := m.spawn(&HostileBehaviour{
		network_id:       'minecraft:zombie'
		detection_radius: 20.0
	}, types.Vector3{0.5, 5, 0.5})
	e.floor_y = -1000 // no fallback floor: must actually stand on the real blocks
	mut max_z := e.pos.z
	for _ in 0 .. 400 {
		m.tick()
		if e.pos.z > max_z {
			max_z = e.pos.z
		}
	}
	assert e.pos.x > 3.5
	assert max_z > 0.8 // detoured through the z=1 gap to get there, not stuck at the wall
}

fn test_save_and_load_entities_round_trip() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_entitydb_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	data := [
		SaveData{
			type_name:  'zombie'
			x:          1.5
			y:          64.0
			z:          -3.25
			velocity_x: 0.1
			health:     14.0
		},
	]
	save_entities(dir, data) or {
		assert false, 'save failed: ${err}'
		return
	}
	loaded := load_entities(dir)
	assert loaded.len == 1
	assert loaded[0].type_name == 'zombie'
	assert loaded[0].x == 1.5
	assert loaded[0].health == 14.0
}

fn test_load_entities_missing_file_returns_empty() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_entitydb_missing_${os.getpid()}')
	loaded := load_entities(dir)
	assert loaded.len == 0
}

fn test_save_snapshot_excludes_projectiles() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	m.spawn(&PassiveBehaviour{ network_id: 'minecraft:pig' }, types.Vector3{0, 5, 0})
	m.spawn(&ProjectileBehaviour{ network_id: 'minecraft:arrow' }, types.Vector3{1, 5, 0})
	saved := m.save_snapshot()
	assert saved.len == 1
	assert saved[0].type_name == 'pig'
}

fn test_restore_from_save_reconstructs_entities() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut reg := new_registry()
	register_defaults(mut reg)
	saved := [
		SaveData{
			type_name:  'zombie'
			x:          2.0
			y:          5.0
			z:          3.0
			velocity_x: 0.2
			pitch:      10.0
			yaw:        20.0
			head_yaw:   20.0
			health:     7.0
		},
	]
	m.restore_from_save(&reg, saved)
	assert m.count() == 1
	restored := m.snapshot()[0]
	assert restored.identifier == 'minecraft:zombie'
	assert restored.pos.x == 2.0
	assert restored.pos.y == 5.0
	assert restored.pos.z == 3.0
	assert restored.velocity.x == f32(0.2)
	assert restored.health == 7.0
	assert restored.pitch == f32(10.0)
}

fn test_restore_from_save_skips_unrecognized_type() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut reg := new_registry()
	register_defaults(mut reg)
	saved := [
		SaveData{
			type_name: 'not_a_real_type'
			x:         0
			y:         5
			z:         0
		},
	]
	m.restore_from_save(&reg, saved)
	assert m.count() == 0
}

fn spawn_item(mut m Manager, id int, count int, max_stack_size int, pos types.Vector3) &Entity {
	stack := types.ItemStack{
		id:    id
		count: count
	}
	return m.spawn(new_item_behaviour(stack, max_stack_size, item_pickup_delay_ticks), pos)
}

fn test_item_identifier_and_dimensions() {
	b := new_item_behaviour(types.ItemStack{ id: 1, count: 1 }, 64, item_pickup_delay_ticks)
	assert b.identifier() == 'minecraft:item'
	assert b.dimensions().width == f32(0.25)
	assert b.dimensions().height == f32(0.25)
	assert b.dimensions().has_collision == true
	assert b.takes_fall_damage() == false
	assert b.despawn_policy().distance == false
}

fn test_item_spawn_packet_is_add_item_actor_not_add_actor() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	e := spawn_item(mut m, 5, 3, 64, types.Vector3{0, 5, 0})
	pkt := e.spawn_packet()
	if pkt is proto.AddItemActorPacket {
		assert pkt.item.id == 5
		assert pkt.item.stack_size == 3
	} else {
		assert false, 'expected AddItemActorPacket, got a different packet type'
	}
}

fn test_item_despawns_after_existence_duration() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := spawn_item(mut m, 5, 1, 64, types.Vector3{0, 5, 0})
	e.age = item_existence_duration_ticks
	m.tick()
	assert m.count() == 0
}

fn test_item_does_not_attempt_pickup_before_delay_elapses() {
	mut host := &FakeHost{}
	host.players[1] = types.Vector3{0, 5, 0}
	host.collect_response = 1
	mut m := new_manager(host)
	mut e := spawn_item(mut m, 5, 1, 64, types.Vector3{0, 5, 0})
	// tick() increments age before ItemBehaviour.tick() checks it
	e.age = item_pickup_delay_ticks - 2
	m.tick()
	assert host.collect_calls == 0
	assert m.count() == 1
}

fn test_item_fully_collected_despawns_and_notifies_pickup() {
	mut host := &FakeHost{}
	host.players[7] = types.Vector3{0, 5, 0}
	host.collect_response = 4
	mut m := new_manager(host)
	mut e := spawn_item(mut m, 5, 4, 64, types.Vector3{0, 5, 0})
	e.age = item_pickup_delay_ticks
	m.tick()
	assert host.collect_calls == 1
	assert host.last_collect_runtime_id == 7
	assert host.last_collect_stack.id == 5
	assert host.take_notify_calls == 1
	assert host.last_take_taker_rid == 7
	assert m.count() == 0
}

fn test_item_partially_collected_shrinks_stack_and_survives() {
	mut host := &FakeHost{}
	host.players[7] = types.Vector3{0, 5, 0}
	host.collect_response = 3 // less than the stack's 10
	mut m := new_manager(host)
	mut e := spawn_item(mut m, 5, 10, 64, types.Vector3{0, 5, 0})
	e.age = item_pickup_delay_ticks
	m.tick()
	assert m.count() == 1
	if e.behaviour is ItemBehaviour {
		assert e.behaviour.stack.count == 7
	} else {
		assert false, 'expected ItemBehaviour'
	}
}

fn test_item_collect_response_zero_leaves_item_untouched() {
	mut host := &FakeHost{}
	host.players[7] = types.Vector3{0, 5, 0}
	host.collect_response = 0 // inventory full, nothing taken
	mut m := new_manager(host)
	mut e := spawn_item(mut m, 5, 10, 64, types.Vector3{0, 5, 0})
	e.age = item_pickup_delay_ticks
	m.tick()
	assert m.count() == 1
	assert host.take_notify_calls == 0
}

fn test_items_merge_when_compatible_and_within_radius() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut a := spawn_item(mut m, 5, 10, 64, types.Vector3{0, 5, 0})
	mut b := spawn_item(mut m, 5, 20, 64, types.Vector3{0.5, 5, 0})
	a.age = item_pickup_delay_ticks
	b.age = item_pickup_delay_ticks
	m.merge_items()

	assert m.count() == 2
	if a.behaviour is ItemBehaviour {
		assert a.behaviour.stack.count == 30
	} else {
		assert false, 'expected ItemBehaviour'
	}
	assert b.dead
}

fn test_items_do_not_merge_with_different_item_ids() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut a := spawn_item(mut m, 5, 10, 64, types.Vector3{0, 5, 0})
	mut b := spawn_item(mut m, 6, 10, 64, types.Vector3{0.5, 5, 0})
	a.age = item_pickup_delay_ticks
	b.age = item_pickup_delay_ticks
	m.merge_items()
	assert m.count() == 2
	assert !a.dead && !b.dead
}

fn test_items_do_not_merge_outside_merge_radius() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut a := spawn_item(mut m, 5, 10, 64, types.Vector3{0, 5, 0})
	mut b := spawn_item(mut m, 5, 10, 64, types.Vector3{20, 5, 0})
	a.age = item_pickup_delay_ticks
	b.age = item_pickup_delay_ticks
	m.merge_items()
	assert m.count() == 2
	assert !a.dead && !b.dead
}

fn test_items_do_not_merge_before_pickup_delay_elapses() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut a := spawn_item(mut m, 5, 10, 64, types.Vector3{0, 5, 0})
	mut b := spawn_item(mut m, 5, 10, 64, types.Vector3{0.5, 5, 0})
	// both left at age 0 - still within pickup_delay_ticks
	m.merge_items()
	assert m.count() == 2
	assert !a.dead && !b.dead
}

fn test_item_merge_only_fills_available_room() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut a := spawn_item(mut m, 5, 60, 64, types.Vector3{0, 5, 0}) // room for 4 more
	mut b := spawn_item(mut m, 5, 10, 64, types.Vector3{0.5, 5, 0})
	a.age = item_pickup_delay_ticks
	b.age = item_pickup_delay_ticks
	m.merge_items()
	assert m.count() == 2 // b keeps its 6 leftover, not fully consumed
	if a.behaviour is ItemBehaviour {
		assert a.behaviour.stack.count == 64
	} else {
		assert false, 'expected ItemBehaviour'
	}
	if b.behaviour is ItemBehaviour {
		assert b.behaviour.stack.count == 6
	} else {
		assert false, 'expected ItemBehaviour'
	}
	assert !b.dead
}

fn test_save_snapshot_excludes_items() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	m.spawn(&PassiveBehaviour{
		network_id: 'minecraft:pig'
	}, types.Vector3{0, 5, 0})
	spawn_item(mut m, 5, 1, 64, types.Vector3{1, 5, 0})
	saved := m.save_snapshot()
	assert saved.len == 1
	assert saved[0].type_name == 'pig'
}

fn test_passive_mob_on_death_drops_registered_loot() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&PassiveBehaviour{
		network_id: 'minecraft:pig'
	}, types.Vector3{0, 5, 0})
	e.hurt(mut host, 20, true, 0)
	assert e.dead
	assert host.dropped_items.len == 1
	assert host.dropped_items[0].item_name == 'minecraft:porkchop'
	assert host.dropped_items[0].count >= 1 && host.dropped_items[0].count <= 3
}

fn test_hostile_mob_on_death_drops_registered_loot() {
	mut host := &FakeHost{}
	mut m := new_manager(host)
	mut e := m.spawn(&HostileBehaviour{
		network_id: 'minecraft:zombie'
	}, types.Vector3{0, 5, 0})
	e.hurt(mut host, 20, true, 0)
	assert e.dead
	for d in host.dropped_items {
		assert d.item_name == 'minecraft:rotten_flesh'
	}
}

fn test_rand_int_range_returns_fixed_value_when_min_equals_max() {
	assert rand_int_range(2, 2) == 2
}

fn test_rand_int_range_stays_within_bounds() {
	for _ in 0 .. 50 {
		v := rand_int_range(1, 3)
		assert v >= 1 && v <= 3
	}
}
