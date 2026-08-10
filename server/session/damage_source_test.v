module session

import time
import protocol.types
import server.effect
import server.internal.auth
import server.internal.gamedata
import server.internal.network
import server.player
import server.world
import server.world.db

fn dst_test_player(name string, health f32, mode int) &player.Player {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: name
	}
	pl.set_health(health)
	pl.set_game_mode(mode)
	return pl
}

fn damage_source_test_world(mut hub Hub) &WorldRuntime {
	w := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(w)
	return hub.world_runtime('world') or { panic('expected world runtime') }
}

fn damage_source_test_session(mut hub Hub, mut wr WorldRuntime, name string, health f32) &NetworkSession {
	mut s := &NetworkSession{
		player:     dst_test_player(name, health, network.game_type_survival)
		runtime_id: hub.allocate_runtime_id()
		hub:        hub
		transport:  &FakeTransport{}
	}
	hub.add(s)
	mut tx := &WorldTx{
		wr: wr
	}
	tx.register_player(s)
	return s
}

fn test_damage_source_death_message_keys() {
	key, params := AttackDamageSource{
		attacker_name: 'Alex'
	}.death_message_key('Steve')
	assert key == '%death.attack.player'
	assert params == ['Steve', 'Alex']

	pkey, pparams := ProjectileDamageSource{
		attacker_name: 'Alex'
	}.death_message_key('Steve')
	assert pkey == '%death.attack.arrow'
	assert pparams == ['Steve', 'Alex']

	mkey, mparams := MagicDamageSource{}.death_message_key('Steve')
	assert mkey == '%death.attack.magic'
	assert mparams == ['Steve']

	fkey, fparams := FallDamageSource{}.death_message_key('Steve')
	assert fkey == '%death.fell.accident.generic'
	assert fparams == ['Steve']

	vkey, vparams := VoidDamageSource{}.death_message_key('Steve')
	assert vkey == '%death.attack.outOfWorld'
	assert vparams == ['Steve']

	dkey, dparams := DrowningDamageSource{}.death_message_key('Steve')
	assert dkey == '%death.attack.drown'
	assert dparams == ['Steve']

	firekey, fireparams := FireDamageSource{}.death_message_key('Steve')
	assert firekey == '%death.attack.onFire'
	assert fireparams == ['Steve']

	lkey, lparams := LavaDamageSource{}.death_message_key('Steve')
	assert lkey == '%death.attack.lava'
	assert lparams == ['Steve']
}

fn test_damage_source_reduction_flags_match_reference_engines() {
	assert AttackDamageSource{}.reduced_by_resistance() == true
	assert AttackDamageSource{}.ignored_by_fire_resistance() == false
	assert ProjectileDamageSource{}.reduced_by_resistance() == true
	assert FallDamageSource{}.reduced_by_resistance() == true
	assert VoidDamageSource{}.reduced_by_resistance() == false
	assert DrowningDamageSource{}.reduced_by_resistance() == false
	assert FireDamageSource{}.reduced_by_resistance() == true
	assert FireDamageSource{}.ignored_by_fire_resistance() == true
	assert LavaDamageSource{}.reduced_by_resistance() == true
	assert LavaDamageSource{}.ignored_by_fire_resistance() == true
}

fn approx_eq(a f32, b f32) bool {
	diff := a - b
	return diff > -0.001 && diff < 0.001
}

fn test_resistance_multiplier_matches_vanilla_20_percent_per_level() {
	assert approx_eq(resistance_multiplier(0), 1.0)
	assert approx_eq(resistance_multiplier(1), 0.8)
	assert approx_eq(resistance_multiplier(3), 0.4)
	assert resistance_multiplier(5) == f32(0) // fully immune from level 5 up
	assert resistance_multiplier(10) == f32(0)
}

fn test_apply_hurt_resistance_reduces_damage() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut victim := damage_source_test_session(mut hub, mut wr, 'Steve', 20)
	victim.player.add_effect_result(effect.new(effect.resistance, 3, 5 * time.second)) // 60% reduction

	victim.apply_hurt(mut wr, 10.0, AttackDamageSource{ attacker_name: 'Alex' })
	assert approx_eq(victim.player.health(), 16.0) // 20 - (10 * 0.4)
}

fn test_apply_hurt_fire_resistance_blocks_fire_sources_entirely() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut victim := damage_source_test_session(mut hub, mut wr, 'Steve', 20)
	victim.player.add_effect_result(effect.new(effect.fire_resistance, 1, 5 * time.second))

	victim.apply_hurt(mut wr, 10.0, LavaDamageSource{})
	assert victim.player.health() == 20 // untouched - fire_resistance blocks it before any reduction math

	victim.apply_hurt(mut wr, 10.0, AttackDamageSource{ attacker_name: 'Alex' })
	assert victim.player.health() == 10 // fire_resistance has no bearing on non-fire sources
}

fn test_apply_hurt_void_death_message() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut victim := damage_source_test_session(mut hub, mut wr, 'Steve', 4)

	victim.apply_hurt(mut wr, 10.0, VoidDamageSource{}) // not reduced by resistance even if it had any
	assert victim.player.health() == 0
	assert victim.player.is_dead()
}

fn test_player_apply_movement_reports_fall_distance_only_on_landing() {
	mut pl := player.new_player()
	pl.reset_position(types.Vector3{0, 10, 0})

	landed_1 := pl.apply_movement(types.Vector3{0, 9, 0}, 0, 0, 0, false)
	assert landed_1 == 0
	landed_2 := pl.apply_movement(types.Vector3{0, 3, 0}, 0, 0, 0, false)
	assert landed_2 == 0
	landed_3 := pl.apply_movement(types.Vector3{0, 3, 0}, 0, 0, 0, true)
	assert landed_3 == 7

	// fall_distance resets after landing
	landed_4 := pl.apply_movement(types.Vector3{0, 1, 0}, 0, 0, 0, false)
	assert landed_4 == 0
	landed_5 := pl.apply_movement(types.Vector3{0, 1, 0}, 0, 0, 0, true)
	assert landed_5 == 2
}

fn test_fall_damage_amount_matches_entity_formula_and_safe_distance() {
	assert fall_damage_amount(3.0) == 0 // exactly the safe distance, no damage
	assert fall_damage_amount(2.9) == 0
	assert fall_damage_amount(4.0) == 1
	assert fall_damage_amount(5.5) == 3 // ceil(2.5)
}

fn test_apply_fall_damage_uses_fall_damage_source_and_creative_is_immune() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut victim := damage_source_test_session(mut hub, mut wr, 'Steve', 20)

	victim.apply_fall_damage(mut wr, 0)
	assert victim.player.health() == 20

	victim.apply_fall_damage(mut wr, 5.0)
	assert victim.player.health() == 18

	victim.player.set_game_mode(network.game_type_creative)
	victim.apply_fall_damage(mut wr, 10.0)
	assert victim.player.health() == 18
}

fn test_tick_breath_drains_and_refills_air_supply() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut s := damage_source_test_session(mut hub, mut wr, 'Steve', 20)
	mut tx := &WorldTx{
		wr: wr
	}

	s.tick_breath(mut tx, true, 0)
	assert s.player.air_supply() == player.max_air_supply_ticks - 1

	s.tick_breath(mut tx, false, 0)
	assert s.player.air_supply() == player.max_air_supply_ticks
}

fn test_tick_breath_damages_once_air_runs_out() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut s := damage_source_test_session(mut hub, mut wr, 'Steve', 20)
	s.player.set_air_supply(0)
	mut tx := &WorldTx{
		wr: wr
	}

	s.tick_breath(mut tx, true, 0) // tick 0 is a multiple of the drowning interval
	assert s.player.health() == 18
}

fn test_tick_burning_lava_contact_damages_once_and_sets_fire() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut s := damage_source_test_session(mut hub, mut wr, 'Steve', 20)
	mut tx := &WorldTx{
		wr: wr
	}

	s.tick_burning(mut tx, true, false)
	assert s.player.health() == 16 // 4 damage, lava_contact_damage
	assert s.player.fire_ticks() == 300

	s.tick_burning(mut tx, true, false)
	assert s.player.health() == 16
	assert s.player.fire_ticks() == 300
}

fn test_tick_burning_water_extinguishes() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut s := damage_source_test_session(mut hub, mut wr, 'Steve', 20)
	s.player.set_fire_ticks(100)
	mut tx := &WorldTx{
		wr: wr
	}

	s.tick_burning(mut tx, false, true)
	assert s.player.fire_ticks() == 0
	assert s.player.health() == 20 // extinguishing itself deals no damage
}

fn test_tick_burning_deals_damage_every_20_ticks_while_burning() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut s := damage_source_test_session(mut hub, mut wr, 'Steve', 20)
	s.player.set_fire_ticks(21)
	mut tx := &WorldTx{
		wr: wr
	}

	s.tick_burning(mut tx, false, false)
	assert s.player.fire_ticks() == 20
	assert s.player.health() == 19 // 1 damage, fire_tick_damage
}

fn test_tick_effects_applies_damage_when_wired_throu_world_tx() {
	mut hub := new_hub(gamedata.GameData{})
	mut wr := damage_source_test_world(mut hub)
	defer {
		hub.close_worlds()
	}
	mut s := damage_source_test_session(mut hub, mut wr, 'Steve', 20)
	s.player.reset_position(types.Vector3{0, void_damage_y - 1, 0})
	mut tx := &WorldTx{
		wr: wr
	}

	tx.tick_effects()
	assert s.player.health() == 16
}
