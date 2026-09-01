module session

// WorldGame holds the per world services that belong to gameplay rather than
// to the actor thread. Right now that is the Hub which owns the sessions
// playing in this world.
//
// It exists because the actor's own work - the job queue, the tick clock,
// continuations, shutdown - never looks a session up and only gameplay
// running on the actor does. A WorldRuntime carries one so world tasks can
// reach the Hub through their WorldTx.
@[heap]
struct WorldGame {
mut:
	hub &Hub = unsafe { nil }
}

fn new_world_game(hub &Hub) &WorldGame {
	return &WorldGame{
		hub: hub
	}
}
