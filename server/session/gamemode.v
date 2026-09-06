module session

import server.player
import server.worldrt

// set_gamemode changes the player's game mode on the owning world's actor.
fn (mut s NetworkSession) set_gamemode(mode player.Gamemode) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	id := s.actor_id()
	worldrt.world_call[bool]('Player.set_gamemode', mut wr, fn [id, mode] (mut tx worldrt.WorldTx) bool {
		mut target := player_for_id(mut tx, id) or { return false }
		target.player.set_gamemode(mut tx, mode)
		return true
	}) or { false }
}
