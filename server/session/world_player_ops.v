module session

// WorldPlayerEntry stores a player's session and binding epoch in the
// owning world's local registry, avoiding separate Hub lookups.
// The session must remain alive until the entry is deregistered.
struct WorldPlayerEntry {
mut:
	session &NetworkSession
	epoch   i64
}

// damage_held_item applies held item damage directly from an active WorldTask.
// Player inventory access is synchronized internally.
fn (mut tx WorldTx) damage_held_item(mut s NetworkSession, amount int) {
	s.damage_held_item(amount)
}

// consume_held_item consumes the held item directly from an active WorldTask,
// avoiding the actor submitting wrapper that would deadlock here.
fn (mut tx WorldTx) consume_held_item(mut s NetworkSession) {
	s.apply_consume_held_item()
}

// register_player and deregister_player are the only ways to mutate the
// world's player registry and must run on its actor. Registration captures
// the session's current binding epoch directly.
fn (mut tx WorldTx) register_player(session &NetworkSession) {
	tx.wr.players[session.runtime_id] = WorldPlayerEntry{
		session: session
		epoch:   session.world_binding().epoch
	}
}

fn (mut tx WorldTx) deregister_player(runtime_id u64) {
	tx.wr.players.delete(runtime_id)
}

// player_for_epoch resolves a player from the world's local registry and
// rejects stale or missing registrations before any side effects occur.
fn (mut tx WorldTx) player_for_epoch(runtime_id u64, epoch i64) ?&NetworkSession {
	entry := tx.wr.players[runtime_id] or { return none }
	if entry.epoch != epoch {
		return none
	}
	return entry.session
}
