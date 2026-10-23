module session

import server.event
import server.internal.gamedata
import server.world
import server.world.db
import server.player
import server.worldrt

fn entity_test_hub_with_world() (&Hub, &worldrt.WorldRuntime) {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	hub.set_default_world('world')
	wr := hub.world_runtime('world') or { panic('expected world runtime') }
	return hub, wr
}

fn test_spawn_succeeds_for_known_type() {
	mut hub, wr := entity_test_hub_with_world()
	ok := hub.spawn_entity('pig', 0, 10, 0)
	assert ok
	assert wr.entities.count() == 1
}

fn test_spawn_fails_for_unknown_type() {
	mut hub, wr := entity_test_hub_with_world()
	ok := hub.spawn_entity('not-a-real-mob', 0, 10, 0)
	assert !ok
	assert wr.entities.count() == 0
}

struct CancelEntitySpawnHandler {
	worldrt.NopHandler
}

fn (mut h CancelEntitySpawnHandler) on_entity_spawn(mut ctx event.Context[event.EntitySpawnData]) {
	ctx.cancel()
}

fn test_cancelled_event_prevents_spawn() {
	mut hub, mut wr := entity_test_hub_with_world()
	wr.handle(&CancelEntitySpawnHandler{})
	ok := hub.spawn_entity('pig', 0, 10, 0)
	assert !ok
	assert wr.entities.count() == 0
}

struct RecordingDespawnHandler {
	worldrt.NopHandler
mut:
	calls           int
	last_identifier string
}

fn (mut h RecordingDespawnHandler) on_entity_despawn(mut ctx event.Context[event.EntityDespawnData]) {
	h.calls++
	h.last_identifier = ctx.val.identifier
}

fn test_despawn_dispatches_entity_despawn_event() {
	mut hub, mut wr := entity_test_hub_with_world()
	mut handler := &RecordingDespawnHandler{}
	wr.handle(handler)
	hub.spawn_entity('pig', 0, 10, 0)
	assert wr.entities.count() == 1

	rid := wr.entities.snapshot()[0].runtime_id
	wr.entities.despawn(rid)

	assert handler.calls == 1
	assert handler.last_identifier == 'minecraft:pig'
}
