module session

import time
import protocol
import protocol.types
import server.effect
import server.internal.gamedata
import server.internal.auth

fn test_add_effect_job_stores_lasting_effect() {
	mut hub := new_hub(gamedata.GameData{})
	mut player := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		health:     20
		effects:    effect.new_manager()
	}
	hub.add(player)

	AddEffectJob{
		runtime_id: 1
		effect:     effect.new(effect.regeneration, 1, 5 * time.second)
	}.run(mut hub)

	active := player.effects.effect(effect.regeneration) or { panic('missing effect') }
	assert active.level() == 1
	assert active.duration_ticks() == 100
}

fn test_lasting_effect_applies_on_tick_not_add() {
	mut hub := new_hub(gamedata.GameData{})
	mut player := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		health:     10
		effects:    effect.new_manager()
	}
	hub.add(player)

	AddEffectJob{
		runtime_id: 1
		effect:     effect.new(effect.regeneration, 1, 5 * time.second)
	}.run(mut hub)
	assert player.health == 10

	TickJob{}.run(mut hub)
	assert player.health == 11
}

fn test_tick_job_expires_effects() {
	mut hub := new_hub(gamedata.GameData{})
	mut player := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		health:     20
		effects:    effect.new_manager()
	}
	hub.add(player)

	AddEffectJob{
		runtime_id: 1
		effect:     effect.new(effect.poison, 1, 50 * time.millisecond)
	}.run(mut hub)

	TickJob{}.run(mut hub)
	assert (player.effects.effect(effect.poison) or { panic('missing poison') }).duration_ticks() == 0
	TickJob{}.run(mut hub)
	if _ := player.effects.effect(effect.poison) {
		assert false
	}
}

fn test_instant_health_applies_without_storing() {
	mut hub := new_hub(gamedata.GameData{})
	player := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		health:     10
		effects:    effect.new_manager()
	}
	hub.add(player)

	AddEffectJob{
		runtime_id: 1
		effect:     effect.new_instant(effect.instant_health, 1)
	}.run(mut hub)

	assert player.health == 14
	assert player.effects.effects().len == 0
}

fn test_consuming_healing_potion_applies_effect_and_returns_bottle() {
	data := gamedata.GameData{
		item_id_by_name: {
			'minecraft:potion':       100
			'minecraft:glass_bottle': 101
		}
	}
	mut hub := new_hub(data)
	mut player := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		health:     10
		effects:    effect.new_manager()
		hub:        hub
	}
	hub.add(player)
	potion := types.ItemStack{
		id:               100
		meta:             21
		count:            1
		block_runtime_id: 0
		raw_extra_data:   []u8{}
	}
	net_id := player.track_stack(potion)
	player.inv_slots[0] = net_id

	changes := player.apply_consume(protocol.StackRequestAction{
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
	replacement, replacement_net := player.inventory_stack_at(0)

	assert player.health == 14
	assert replacement.id == 101
	assert replacement.count == 1
	assert changes[0].info.stack_network_id == replacement_net
}
