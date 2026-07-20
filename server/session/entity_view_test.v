module session

import server.event
import server.internal.gamedata

fn test_spawn_succeeds_for_known_type() {
	mut hub := new_hub(gamedata.GameData{})
	ok := hub.spawn_entity('pig', 0, 10, 0)
	assert ok
	assert hub.entities.count() == 1
}

fn test_spawn_fails_for_unknown_type() {
	mut hub := new_hub(gamedata.GameData{})
	ok := hub.spawn_entity('not-a-real-mob', 0, 10, 0)
	assert !ok
	assert hub.entities.count() == 0
}

struct CancelEntitySpawnHandler {
	event.NopHandler
}

fn (mut h CancelEntitySpawnHandler) on_entity_spawn(mut ctx event.Context[event.EntitySpawnData]) {
	ctx.cancel()
}

fn test_cancelled_event_prevents_spawn() {
	mut hub := new_hub(gamedata.GameData{})
	hub.events.register(&CancelEntitySpawnHandler{}, .normal)
	ok := hub.spawn_entity('pig', 0, 10, 0)
	assert !ok
	assert hub.entities.count() == 0
}

struct RecordingDespawnHandler {
	event.NopHandler
mut:
	calls          int
	last_identifier string
}

fn (mut h RecordingDespawnHandler) on_entity_despawn(mut ctx event.Context[event.EntityDespawnData]) {
	h.calls++
	h.last_identifier = ctx.val.identifier
}

fn test_despawn_dispatches_entity_despawn_event() {
	mut hub := new_hub(gamedata.GameData{})
	mut handler := &RecordingDespawnHandler{}
	hub.events.register(handler, .normal)
	hub.spawn_entity('pig', 0, 10, 0)
	assert hub.entities.count() == 1

	rid := hub.entities.snapshot()[0].runtime_id
	hub.entities.despawn(rid)

	assert handler.calls == 1
	assert handler.last_identifier == 'minecraft:pig'
}
