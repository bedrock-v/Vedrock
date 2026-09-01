module session

import server.event

// WorldGame holds the per world services that belong to gameplay rather than
// to the actor thread: the world's own event bus and the Hub that owns the
// sessions playing in it. Both live here because the actor's own work.
// The job queue, the tick clock, continuations, shutdownnever dispatches an
// event or looks up a session and only gameplay running on the actor does.
//
// A WorldRuntime carries one so world tasks can reach these through their
// WorldTx.
@[heap]
struct WorldGame {
mut:
	hub    &Hub       = unsafe { nil }
	events &event.Bus = unsafe { nil }
}

fn new_world_game(hub &Hub) &WorldGame {
	return &WorldGame{
		hub:    hub
		events: event.new_bus()
	}
}

// register_world_event submits event bus mutation to the owning runtime so
// registration is serialized against dispatch.
//
// A function rather than a WorldRuntime method: the bus belongs to gameplay
// and the actor is not allowed to name an event type.
fn register_world_event(mut wr WorldRuntime, handler event.Handler, priority event.Priority) {
	wr.submit(RegisterEventTask{
		handler:  handler
		priority: priority
	})
}

struct RegisterEventTask {
	handler  event.Handler
	priority event.Priority
}

fn (t RegisterEventTask) name() string {
	return 'RegisterEventTask'
}

fn (t RegisterEventTask) run(mut tx WorldTx) {
	tx.wr.game.events.register(t.handler, t.priority)
}

// unregister_world_event submits event-bus mutation to the owning runtime so
// removal is serialized against dispatch.
fn unregister_world_event(mut wr WorldRuntime, handler event.Handler) {
	wr.submit(UnregisterEventTask{
		handler: handler
	})
}

struct UnregisterEventTask {
	handler event.Handler
}

fn (t UnregisterEventTask) name() string {
	return 'UnregisterEventTask'
}

fn (t UnregisterEventTask) run(mut tx WorldTx) {
	tx.wr.game.events.unregister(t.handler)
}
