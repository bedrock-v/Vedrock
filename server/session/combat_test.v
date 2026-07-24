module session

import time
import protocol
import protocol.types
import server.event
import server.internal.gamedata
import server.player
import server.internal.auth
import server.world
import server.world.db

fn wait_for_sent_len(transport &FakeTransport, want int, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for transport.sent.len < want {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return transport.sent.len >= want
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return transport.sent.len >= want
		}
	}
	return true
}

fn make_combat_test_player(name string, health f32, mode int) &player.Player {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: name
	}
	pl.set_health(health)
	pl.set_game_mode(mode)
	return pl
}

fn test_is_critical_requires_falling_and_survival() {
	mut pl := player.new_player()
	pl.set_game_mode(protocol.game_type_survival)
	mut s := &NetworkSession{
		player: pl
	}
	s.player.apply_movement(types.Vector3{0.0, 1.0, 0.0}, 0.0, 0.0, 0.0)
	s.player.apply_movement(types.Vector3{0.0, 0.8, 0.0}, 0.0, 0.0, 0.0)
	assert s.is_critical()

	s.player.apply_movement(types.Vector3{0.0, 0.8, 0.0}, 0.0, 0.0, 0.0)
	assert !s.is_critical()

	s.player.apply_movement(types.Vector3{0.0, 0.6, 0.0}, 0.0, 0.0, 0.0)
	s.player.set_game_mode(protocol.game_type_creative)
	assert !s.is_critical()
}

fn test_handle_attack_rejects_out_of_reach() {
	mut hub := new_hub(gamedata.GameData{})
	mut attacker := &NetworkSession{
		player:     make_combat_test_player('Alex', 20, 0)
		runtime_id: 1
		hub:        hub
	}
	attacker.player.reset_position(types.Vector3{0.0, 0.0, 0.0})
	mut victim := &NetworkSession{
		player:     make_combat_test_player('Steve', 20, 0)
		runtime_id: 2
		hub:        hub
		spawned:    true
	}
	victim.player.reset_position(types.Vector3{100.0, 0.0, 0.0})
	hub.add(attacker)
	hub.add(victim)

	// Out of reach returns before a DamageJob is ever submitted, so this is
	// deterministic without needing to poll the actor thread.
	attacker.handle_attack(2)!
	assert victim.player.health() == 20
}

fn combat_test_session(mut hub Hub, mut wr WorldRuntime, name string, health f32, mode int) &NetworkSession {
	mut s := &NetworkSession{
		player:        make_combat_test_player(name, health, mode)
		runtime_id:    hub.allocate_runtime_id()
		hub:           hub
		spawned:       true
		world:         wr.world
		world_runtime: wr
		transport:     &FakeTransport{}
	}
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn test_handle_attack_cancelled_event_does_no_damage() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	mut wr := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	defer {
		hub.close_worlds()
	}
	wr.events.register(&CancelAttackHandler{}, .normal)

	mut attacker := combat_test_session(mut hub, mut wr, 'Alex', 20, 0)
	attacker.player.reset_position(types.Vector3{0.0, 0.0, 0.0})
	mut victim := combat_test_session(mut hub, mut wr, 'Steve', 20, 0)
	victim.player.reset_position(types.Vector3{1.0, 0.0, 0.0})

	attacker.handle_attack(victim.runtime_id)!
	// world_call as a synchronization barrier, guarantees the attack task
	// above has actually landed before checking state.
	world_call[bool](mut wr, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert victim.player.health() == 20
}

struct CancelAttackHandler {
	event.NopHandler
}

fn (mut h CancelAttackHandler) on_player_attack(mut ctx event.Context[event.AttackData]) {
	ctx.cancel()
}

fn apply_hurt_test_world(mut hub Hub) &WorldRuntime {
	w := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(w)
	return hub.world_runtime('world') or { panic('expected world runtime') }
}

fn test_apply_hurt_clamps_health_at_zero_and_kills() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := apply_hurt_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut transport := &FakeTransport{}
	mut victim := &NetworkSession{
		player:     make_combat_test_player('Steve', 5, protocol.game_type_survival)
		runtime_id: 2
		hub:        hub
		transport:  transport
	}
	hub.add(victim)

	victim.apply_hurt(mut wr, 10.0, 'Alex')
	assert victim.player.health() == 0
	assert victim.player.is_dead()
}

fn test_apply_hurt_creative_is_immune() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := apply_hurt_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut victim := &NetworkSession{
		player:     make_combat_test_player('Steve', 20, protocol.game_type_creative)
		runtime_id: 2
		hub:        hub
	}
	hub.add(victim)

	victim.apply_hurt(mut wr, 10.0, 'Alex')
	assert victim.player.health() == 20
	assert !victim.player.is_dead()
}

fn test_apply_hurt_cancelled_event_prevents_damage() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := apply_hurt_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	wr.events.register(&CancelHurtHandler{}, .normal)
	mut victim := &NetworkSession{
		player:     make_combat_test_player('Steve', 20, protocol.game_type_survival)
		runtime_id: 2
		hub:        hub
	}
	hub.add(victim)

	victim.apply_hurt(mut wr, 10.0, 'Alex')
	assert victim.player.health() == 20
	assert !victim.player.is_dead()
}

struct CancelHurtHandler {
	event.NopHandler
}

fn (mut h CancelHurtHandler) on_player_hurt(mut ctx event.Context[event.HurtData]) {
	ctx.cancel()
}

fn test_apply_death_cancelled_prevents_death_entirely() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := apply_hurt_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	wr.events.register(&CancelDeathHandler{}, .normal)
	mut victim := &NetworkSession{
		player:     make_combat_test_player('Steve', 0, 0)
		runtime_id: 2
		hub:        hub
	}
	hub.add(victim)

	victim.apply_death(mut wr, '%death.attack.player', ['Steve', 'Alex'])
	// Cancelling DeathData now prevents death outright, dead/has_last_death
	// stay false, and the animation broadcast is skipped along with the
	// message.
	assert !victim.player.is_dead()
	assert !victim.player.has_last_death()
}

struct CancelDeathHandler {
	event.NopHandler
}

fn (mut h CancelDeathHandler) on_player_death(mut ctx event.Context[event.DeathData]) {
	ctx.cancel()
}

fn test_apply_death_recs_last_death_pos_when_not_cancelled() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := apply_hurt_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut victim := &NetworkSession{
		player:     make_combat_test_player('Steve', 0, 0)
		runtime_id: 2
		hub:        hub
	}
	victim.player.reset_position(types.Vector3{3.0, 4.0, 5.0})
	hub.add(victim)

	victim.apply_death(mut wr, '%death.attack.player', ['Steve', 'Alex'])
	assert victim.player.is_dead()
	assert victim.player.has_last_death()
	assert victim.player.last_death_pos() == types.Vector3{3.0, 4.0, 5.0}
}

fn test_apply_respawn_resets_health_and_position() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := apply_hurt_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut transport := &FakeTransport{}
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Steve'
	}
	pl.set_health(0)
	pl.set_dead(true)
	mut victim := &NetworkSession{
		player:     pl
		runtime_id: 2
		hub:        hub
		transport:  transport
		generator:  world.VoidGenerator{}
	}
	// Give it a nonzero vy the same way real movement would, to prove
	// apply_respawn actually resets it rather than it trivially starting at 0.
	victim.player.apply_movement(types.Vector3{0.0, 1.0, 0.0}, 0.0, 0.0, 0.0)
	victim.player.apply_movement(types.Vector3{0.0, 0.0, 0.0}, 0.0, 0.0, 0.0)
	hub.add(victim)

	victim.apply_respawn(mut wr)
	assert !victim.player.is_dead()
	assert victim.player.health() == 20.0
	assert victim.player.movement().vy == 0.0
	assert victim.player.movement().position.y == f32(world.VoidGenerator{}.spawn_y()) +
		player_eye_height
}

fn test_apply_respawn_is_noop_when_not_dead() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := apply_hurt_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Steve'
	}
	pl.set_health(20)
	pl.set_dead(false)
	mut victim := &NetworkSession{
		player:     pl
		runtime_id: 2
		hub:        hub
		generator:  world.VoidGenerator{}
	}
	hub.add(victim)

	victim.apply_respawn(mut wr)
	assert victim.player.health() == 20
}

fn test_apply_knockback_degenerate_case_has_no_horizontal_component() {
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:    player.new_player()
		transport: transport
	}
	s.player.reset_position(types.Vector3{0.0, 0.0, 0.0})
	s.apply_knockback(types.Vector3{0.0, 0.0, 0.0}, knockback_horizontal, knockback_vertical)
	assert wait_for_sent_len(transport, 1, 5000)
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
		player:    player.new_player()
		transport: transport
	}
	s.player.reset_position(types.Vector3{10.0, 0.0, 0.0})
	s.apply_knockback(types.Vector3{0.0, 0.0, 0.0}, knockback_horizontal, knockback_vertical)
	assert wait_for_sent_len(transport, 1, 5000)
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
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	wr := hub.world_runtime('world') or { panic('expected world runtime') }
	cow_behaviour := hub.entity_registry.create('cow') or { panic('missing cow behaviour') }
	cow := wr.entities.spawn(cow_behaviour, types.Vector3{1.0, 0.0, 0.0})
	mut sess := &NetworkSession{
		player:        make_combat_test_player('Alex', 20, 0)
		runtime_id:    1
		hub:           hub
		world:         target
		world_runtime: wr
	}
	sess.player.reset_position(types.Vector3{0.0, 0.0, 0.0})
	hub.add(sess)
	bucket := types.ItemStack{
		id:    200
		count: 1
	}
	net_id := sess.player.track_stack(bucket)
	sess.player.set_slot(0, net_id)

	sess.handle_entity_interact(cow.runtime_id)

	held, _ := sess.inventory_stack_at(sess.player.held_slot())
	assert held.id == 201
}

fn test_handle_entity_interact_non_cow_is_noop() {
	mut hub := new_hub(bucket_test_data())
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	wr := hub.world_runtime('world') or { panic('expected world runtime') }
	pig_behaviour := hub.entity_registry.create('pig') or { panic('missing pig behaviour') }
	pig := wr.entities.spawn(pig_behaviour, types.Vector3{1.0, 0.0, 0.0})
	mut sess := &NetworkSession{
		player:        make_combat_test_player('Alex', 20, 0)
		runtime_id:    1
		hub:           hub
		world:         target
		world_runtime: wr
	}
	sess.player.reset_position(types.Vector3{0.0, 0.0, 0.0})
	hub.add(sess)
	bucket := types.ItemStack{
		id:    200
		count: 1
	}
	net_id := sess.player.track_stack(bucket)
	sess.player.set_slot(0, net_id)

	sess.handle_entity_interact(pig.runtime_id)

	held, _ := sess.inventory_stack_at(sess.player.held_slot())
	assert held.id == 200
}

fn test_handle_entity_interact_out_of_reach_is_noop() {
	mut hub := new_hub(bucket_test_data())
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	wr := hub.world_runtime('world') or { panic('expected world runtime') }
	cow_behaviour := hub.entity_registry.create('cow') or { panic('missing cow behaviour') }
	cow := wr.entities.spawn(cow_behaviour, types.Vector3{100.0, 0.0, 0.0})
	mut sess := &NetworkSession{
		player:        make_combat_test_player('Alex', 20, 0)
		runtime_id:    1
		hub:           hub
		world:         target
		world_runtime: wr
	}
	sess.player.reset_position(types.Vector3{0.0, 0.0, 0.0})
	hub.add(sess)
	bucket := types.ItemStack{
		id:    200
		count: 1
	}
	net_id := sess.player.track_stack(bucket)
	sess.player.set_slot(0, net_id)

	sess.handle_entity_interact(cow.runtime_id)

	held, _ := sess.inventory_stack_at(sess.player.held_slot())
	assert held.id == 200
}
