module session

import server.entity
import server.worldrt

// damage_held_item applies held item damage directly from an active worldrt.WorldTask.
// Player inventory access is synchronized internally.
fn damage_held_item(mut s NetworkSession, amount int) {
	s.damage_held_item(amount)
}

// consume_held_item consumes the held item directly from an active worldrt.WorldTask.
// The mutation touches only this player's inventory which is synchronized
// internally.
fn consume_held_item(mut s NetworkSession) {
	s.apply_consume_held_item()
}

// register_player and deregister_player are the only ways to mutate the
// world's player registry and must run on its actor. Registration captures
// the session's current binding epoch directly.
fn register_player(mut tx worldrt.WorldTx, session &NetworkSession) {
	tx.wr.entities.register_player_actor(session, session.runtime_id, session.world_binding().epoch)
	tx.wr.publish_player_count()
}

fn deregister_player(mut tx worldrt.WorldTx, runtime_id u64) {
	tx.wr.entities.deregister_player_actor(runtime_id)
	tx.wr.publish_player_count()
}

// player_for_epoch resolves a player from the world's local registry and
// rejects stale or missing registrations before any side effects occur.
fn player_for_epoch(mut tx worldrt.WorldTx, runtime_id u64, epoch i64) ?&NetworkSession {
	mut a := tx.wr.entities.player_actor_for_epoch(runtime_id, epoch) or { return none }
	return as_network_session(mut a)
}

fn as_network_session(mut a entity.Actor) ?&NetworkSession {
	if mut a is NetworkSession {
		return a
	}
	return none
}
