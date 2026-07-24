module session

import time
import protocol
import protocol.types
import server.effect
import server.event
import server.internal.gamedata
import server.player
import server.internal.auth
import server.world
import server.world.db

fn make_effects_test_player(name string, health f32) &player.Player {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: name
	}
	pl.set_health(health)
	return pl
}

fn effects_test_session(mut hub Hub, name string, health f32) (&NetworkSession, &WorldRuntime) {
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut sess := &NetworkSession{
		player:        make_effects_test_player(name, health)
		runtime_id:    hub.allocate_runtime_id()
		hub:           hub
		world:         wr.world
		world_runtime: wr
	}
	hub.add(sess)
	world_call[bool](mut wr, fn [sess] (mut tx WorldTx) bool {
		tx.register_player(sess)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return sess, wr
}

fn add_effect_directly(wr &WorldRuntime, rid u64, e effect.Effect) {
	mut tx := &WorldTx{
		wr: wr
	}

	PlayerAddEffectTask{
		runtime_id: rid
		epoch:      0
		effect:     e
	}.run(mut tx)
}

fn remove_effect_directly(wr &WorldRuntime, rid u64, typ effect.Type) {
	mut tx := &WorldTx{
		wr: wr
	}

	PlayerRemoveEffectTask{
		runtime_id: rid
		epoch:      0
		typ:        typ
	}.run(mut tx)
}

fn tick_effects_directly(wr &WorldRuntime) {
	mut tx := &WorldTx{
		wr: wr
	}
	tx.tick_effects()
}

fn test_add_effect_job_stores_lasting_effect() {
	mut hub := new_hub(gamedata.GameData{})
	mut sess, wr := effects_test_session(mut hub, 'Alex', 20)
	defer {
		hub.close_worlds()
	}

	add_effect_directly(wr, sess.runtime_id, effect.new(effect.regeneration, 1, 5 * time.second))

	active := sess.player.effect(effect.regeneration) or { panic('missing effect') }
	assert active.level() == 1
	assert active.duration_ticks() == 100
}

fn test_lasting_effect_applies_on_tick_not_add() {
	mut hub := new_hub(gamedata.GameData{})
	mut sess, wr := effects_test_session(mut hub, 'Alex', 10)
	defer {
		hub.close_worlds()
	}

	add_effect_directly(wr, sess.runtime_id, effect.new(effect.regeneration, 1, 5 * time.second))
	assert sess.player.health() == 10

	tick_effects_directly(wr)
	assert sess.player.health() == 11
}

fn test_world_tick_expires_effects() {
	mut hub := new_hub(gamedata.GameData{})
	mut sess, wr := effects_test_session(mut hub, 'Alex', 20)
	defer {
		hub.close_worlds()
	}

	add_effect_directly(wr, sess.runtime_id, effect.new(effect.poison, 1, 50 * time.millisecond))

	tick_effects_directly(wr)
	assert (sess.player.effect(effect.poison) or { panic('missing poison') }).duration_ticks() == 0
	tick_effects_directly(wr)
	if _ := sess.player.effect(effect.poison) {
		assert false
	}
}

fn test_instant_health_applies_without_storing() {
	mut hub := new_hub(gamedata.GameData{})
	mut sess, wr := effects_test_session(mut hub, 'Alex', 10)
	defer {
		hub.close_worlds()
	}

	add_effect_directly(wr, sess.runtime_id, effect.new_instant(effect.instant_health, 1))

	assert sess.player.health() == 14
	assert sess.player.active_effects().len == 0
}

fn test_consuming_healing_potion_applies_effect_and_returns_bottle() {
	data := gamedata.GameData{
		item_id_by_name: {
			'minecraft:potion':       100
			'minecraft:glass_bottle': 101
		}
	}
	mut hub := new_hub(data)
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}
	mut sess := &NetworkSession{
		player:     make_effects_test_player('Alex', 10)
		runtime_id: 1
		hub:        hub
	}
	hub.add(sess)
	potion := types.ItemStack{
		id:               100
		meta:             21
		count:            1
		block_runtime_id: 0
		raw_extra_data:   []u8{}
	}
	net_id := sess.player.track_stack(potion)
	sess.player.set_slot(0, net_id)

	changes := sess.apply_consume(mut wr, protocol.StackRequestAction{
		action_type: protocol.stack_request_action_consume
		count:       1
		source:      protocol.StackRequestSlotInfo{
			container:        types.FullContainerName{
				container_id: container_hotbar
			}
			slot:             0
			stack_network_id: net_id
		}
	})
	replacement, replacement_net := sess.inventory_stack_at(0)

	assert sess.player.health() == 14
	assert replacement.id == 101
	assert replacement.count == 1
	assert changes[0].info.stack_network_id == replacement_net
}

struct CancelEffectAddHandler {
	event.NopHandler
}

fn (mut h CancelEffectAddHandler) on_effect_add(mut ctx event.Context[event.EffectAddData]) {
	ctx.cancel()
}

fn test_cancelled_effect_add_rejects_effect() {
	mut hub := new_hub(gamedata.GameData{})
	mut sess, wr := effects_test_session(mut hub, 'Alex', 20)
	defer {
		hub.close_worlds()
	}
	wr.events.register(&CancelEffectAddHandler{}, .normal)

	add_effect_directly(wr, sess.runtime_id, effect.new(effect.regeneration, 1, 5 * time.second))

	if _ := sess.player.effect(effect.regeneration) {
		assert false
	}
}

struct CancelEffectRemoveHandler {
	event.NopHandler
}

fn (mut h CancelEffectRemoveHandler) on_effect_remove(mut ctx event.Context[event.EffectRemoveData]) {
	ctx.cancel()
}

fn test_cancelled_effect_remove_keeps_effect() {
	mut hub := new_hub(gamedata.GameData{})
	mut sess, wr := effects_test_session(mut hub, 'Alex', 20)
	defer {
		hub.close_worlds()
	}

	add_effect_directly(wr, sess.runtime_id, effect.new(effect.regeneration, 1, 5 * time.second))
	active := sess.player.effect(effect.regeneration) or { panic('missing effect') }
	assert active.level() == 1

	wr.events.register(&CancelEffectRemoveHandler{}, .normal)

	remove_effect_directly(wr, sess.runtime_id, effect.regeneration)

	still_active := sess.player.effect(effect.regeneration) or {
		panic('effect should still be active')
	}
	assert still_active.level() == 1
}
