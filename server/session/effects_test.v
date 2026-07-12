module session

import time
import server.effect
import server.internal.gamedata
import server.internal.auth

fn test_add_effect_job_stores_lasting_effect() {
	mut hub := new_hub(gamedata.GameData{})
	player := &NetworkSession{
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
		effect:     effect.new(effect.regeneration, 1, 5 * time.second)
	}.run(mut hub)
	assert player.health == 10

	TickJob{}.run(mut hub)
	assert player.health == 11
}

fn test_tick_job_expires_effects() {
	mut hub := new_hub(gamedata.GameData{})
	player := &NetworkSession{
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
