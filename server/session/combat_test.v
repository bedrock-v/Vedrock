module session

import protocol
import protocol.types
import server.event
import server.internal.gamedata
import server.internal.auth
import server.world

fn test_is_critical_requires_falling_and_survival() {
	mut s := &NetworkSession{
		game_mode: protocol.game_type_survival
	}
	s.vy = -0.2
	assert s.is_critical()

	s.vy = 0.0
	assert !s.is_critical()

	s.vy = -0.2
	s.game_mode = protocol.game_type_creative
	assert !s.is_critical()
}

fn test_handle_attack_rejects_out_of_reach() {
	mut hub := new_hub(gamedata.GameData{})
	mut attacker := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		hub:        hub
		health:     20
		position:   types.Vector3{0.0, 0.0, 0.0}
	}
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		health:     20
		spawned:    true
		position:   types.Vector3{100.0, 0.0, 0.0}
	}
	hub.add(attacker)
	hub.add(victim)

	// Out of reach returns before a DamageJob is ever submitted, so this is
	// deterministic without needing to poll the actor thread.
	attacker.handle_attack(2)!
	assert victim.health == 20
}

fn test_handle_attack_cancelled_event_does_no_damage() {
	mut hub := new_hub(gamedata.GameData{})
	hub.events.register(&CancelAttackHandler{}, .normal)
	mut attacker := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		hub:        hub
		health:     20
		position:   types.Vector3{0.0, 0.0, 0.0}
	}
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		health:     20
		spawned:    true
		position:   types.Vector3{1.0, 0.0, 0.0}
	}
	hub.add(attacker)
	hub.add(victim)

	attacker.handle_attack(2)!
	assert victim.health == 20
}

struct CancelAttackHandler {
	event.NopHandler
}

fn (mut h CancelAttackHandler) on_player_attack(mut ctx event.Context[event.AttackData]) {
	ctx.cancel()
}

fn test_take_damage_clamps_health_at_zero_and_kills() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		transport:  transport
		health:     5
		game_mode:  protocol.game_type_survival
	}
	hub.add(victim)

	victim.take_damage(10.0, 'Alex')
	assert victim.health == 0
	assert victim.dead
}

fn test_take_damage_creative_is_immune() {
	mut hub := new_hub(gamedata.GameData{})
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		health:     20
		game_mode:  protocol.game_type_creative
	}
	hub.add(victim)

	victim.take_damage(10.0, 'Alex')
	assert victim.health == 20
	assert !victim.dead
}

fn test_take_damage_cancelled_event_prevents_damage() {
	mut hub := new_hub(gamedata.GameData{})
	hub.events.register(&CancelHurtHandler{}, .normal)
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		health:     20
		game_mode:  protocol.game_type_survival
	}
	hub.add(victim)

	victim.take_damage(10.0, 'Alex')
	assert victim.health == 20
	assert !victim.dead
}

struct CancelHurtHandler {
	event.NopHandler
}

fn (mut h CancelHurtHandler) on_player_hurt(mut ctx event.Context[event.HurtData]) {
	ctx.cancel()
}

fn test_die_cancelled_prevents_death_entirely() {
	mut hub := new_hub(gamedata.GameData{})
	hub.events.register(&CancelDeathHandler{}, .normal)
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		health:     0
	}
	hub.add(victim)

	victim.die('%death.attack.player', ['Steve', 'Alex'])
	// Cancelling DeathData now prevents death outright, dead/has_last_death
	// stay false, and the animation broadcast is skipped along with the
	// message.
	assert !victim.dead
	assert !victim.has_last_death
}

struct CancelDeathHandler {
	event.NopHandler
}

fn (mut h CancelDeathHandler) on_player_death(mut ctx event.Context[event.DeathData]) {
	ctx.cancel()
}

fn test_die_records_last_death_position_when_not_cancelled() {
	mut hub := new_hub(gamedata.GameData{})
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		health:     0
		position:   types.Vector3{3.0, 4.0, 5.0}
	}
	hub.add(victim)

	victim.die('%death.attack.player', ['Steve', 'Alex'])
	assert victim.dead
	assert victim.has_last_death
	assert victim.last_death_pos == types.Vector3{3.0, 4.0, 5.0}
}

fn test_respawn_resets_health_and_position() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		transport:  transport
		health:     0
		dead:       true
		generator:  world.VoidGenerator{}
		vy:         -1.0
	}
	hub.add(victim)

	victim.respawn()
	assert !victim.dead
	assert victim.health == 20.0
	assert victim.vy == 0.0
	assert victim.position.y == f32(world.VoidGenerator{}.spawn_y()) + player_eye_height
}

fn test_respawn_is_noop_when_not_dead() {
	mut hub := new_hub(gamedata.GameData{})
	mut victim := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		health:     20
		dead:       false
		generator:  world.VoidGenerator{}
	}
	hub.add(victim)

	victim.respawn()
	assert victim.health == 20
}

fn test_apply_knockback_degenerate_case_has_no_horizontal_component() {
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		transport: transport
		position:  types.Vector3{0.0, 0.0, 0.0}
	}
	s.apply_knockback(types.Vector3{0.0, 0.0, 0.0}, knockback_horizontal, knockback_vertical)
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.SetActorMotionPacket {
		assert sent.motion.x == 0.0
		assert sent.motion.z == 0.0
		assert sent.motion.y == knockback_vertical
	} else {
		assert false
	}
}

fn test_apply_knockback_pushes_away_from_attacker() {
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		transport: transport
		position:  types.Vector3{10.0, 0.0, 0.0}
	}
	s.apply_knockback(types.Vector3{0.0, 0.0, 0.0}, knockback_horizontal, knockback_vertical)
	sent := transport.sent[0]
	if sent is protocol.SetActorMotionPacket {
		assert sent.motion.x == knockback_horizontal
		assert sent.motion.z == 0.0
	} else {
		assert false
	}
}

fn test_weapon_damage_heuristic_by_tier() {
	assert weapon_damage_heuristic('minecraft:wooden_sword') == 5.0
	assert weapon_damage_heuristic('minecraft:stone_sword') == 6.0
	assert weapon_damage_heuristic('minecraft:iron_sword') == 7.0
	assert weapon_damage_heuristic('minecraft:diamond_sword') == 8.0
	assert weapon_damage_heuristic('minecraft:netherite_sword') == 9.0
}

fn test_weapon_damage_heuristic_axes() {
	assert weapon_damage_heuristic('minecraft:wooden_axe') == 4.0
	assert weapon_damage_heuristic('minecraft:iron_axe') == 6.0
	assert weapon_damage_heuristic('minecraft:netherite_axe') == 8.0
}

fn test_weapon_damage_heuristic_defaults_to_bare_hand() {
	assert weapon_damage_heuristic('minecraft:stick') == 1.0
	assert weapon_damage_heuristic('minecraft:air') == 1.0
}

fn test_material_tier_by_name_substring() {
	assert material_tier('minecraft:wooden_sword') == 0
	assert material_tier('minecraft:stone_pickaxe') == 1
	assert material_tier('minecraft:iron_axe') == 2
	assert material_tier('minecraft:diamond_sword') == 3
	assert material_tier('minecraft:netherite_sword') == 4
}

fn bucket_test_data() gamedata.GameData {
	return gamedata.GameData{
		item_id_by_name: {
			'minecraft:bucket':      200
			'minecraft:milk_bucket': 201
		}
	}
}

fn test_handle_entity_interact_milks_cow_with_bucket() {
	mut hub := new_hub(bucket_test_data())
	cow_behaviour := hub.entity_registry.create('cow') or { panic('missing cow behaviour') }
	cow := hub.entities.spawn(cow_behaviour, types.Vector3{1.0, 0.0, 0.0})
	mut player := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		hub:        hub
		position:   types.Vector3{0.0, 0.0, 0.0}
	}
	hub.add(player)
	bucket := types.ItemStack{
		id:    200
		count: 1
	}
	net_id := player.track_stack(bucket)
	player.inv_slots[0] = net_id

	player.handle_entity_interact(cow.runtime_id)

	held, _ := player.inventory_stack_at(player.held_slot)
	assert held.id == 201
}

fn test_handle_entity_interact_non_cow_is_noop() {
	mut hub := new_hub(bucket_test_data())
	pig_behaviour := hub.entity_registry.create('pig') or { panic('missing pig behaviour') }
	pig := hub.entities.spawn(pig_behaviour, types.Vector3{1.0, 0.0, 0.0})
	mut player := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		hub:        hub
		position:   types.Vector3{0.0, 0.0, 0.0}
	}
	hub.add(player)
	bucket := types.ItemStack{
		id:    200
		count: 1
	}
	net_id := player.track_stack(bucket)
	player.inv_slots[0] = net_id

	player.handle_entity_interact(pig.runtime_id)

	held, _ := player.inventory_stack_at(player.held_slot)
	assert held.id == 200
}

fn test_handle_entity_interact_out_of_reach_is_noop() {
	mut hub := new_hub(bucket_test_data())
	cow_behaviour := hub.entity_registry.create('cow') or { panic('missing cow behaviour') }
	cow := hub.entities.spawn(cow_behaviour, types.Vector3{100.0, 0.0, 0.0})
	mut player := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		hub:        hub
		position:   types.Vector3{0.0, 0.0, 0.0}
	}
	hub.add(player)
	bucket := types.ItemStack{
		id:    200
		count: 1
	}
	net_id := player.track_stack(bucket)
	player.inv_slots[0] = net_id

	player.handle_entity_interact(cow.runtime_id)

	held, _ := player.inventory_stack_at(player.held_slot)
	assert held.id == 200
}
