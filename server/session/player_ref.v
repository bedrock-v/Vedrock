module session

import bedrock_v.protocol.types
import server.player
import server.worldrt

// PlayerRef is a stale checked reference to a player. It remains valid only
// for the world membership generation captured when it was created.
//
// Operations fail if the player disconnects or changes worlds, preventing
// stale references from resolving to another session or membership.
pub struct PlayerRef {
	runtime_id u64
	epoch      i64
	name_      string
	world_     World
	hub_       &Hub = unsafe { nil }
}

// player_ref_for builds a PlayerRef for session's current world membership
// generation.
fn player_ref_for(s &NetworkSession) PlayerRef {
	binding := s.world_binding()
	return PlayerRef{
		runtime_id: s.runtime_id
		epoch:      binding.epoch
		name_:      s.name()
		hub_:       s.hub
		world_:     World{
			runtime: binding.world_runtime
		}
	}
}

// player_ref looks up the player currently connected under name and
// returns a PlayerRef for their current world membership generation.
pub fn (mut h Hub) player_ref(name string) ?PlayerRef {
	s := h.session_by_name(name) or { return none }
	return player_ref_for(s)
}

// player_refs returns a PlayerRef for every currently connected session.
// The lookup reads session state directly and doesn't involve a world actor.
pub fn (mut h Hub) player_refs() []PlayerRef {
	mut out := []PlayerRef{}
	for mut s in h.snapshot() {
		out << player_ref_for(s)
	}
	return out
}

fn (p PlayerRef) resolve() !&NetworkSession {
	mut hub := unsafe { p.hub_ }
	s := hub.session_by_runtime(p.runtime_id) or { return error('player is no longer connected') }
	if s.world_binding().epoch != p.epoch {
		return error('player has since left this world')
	}
	return s
}

// name is the player's display name, captured when this PlayerRef was
// created. Stays valid even after the player disconnects.
pub fn (p PlayerRef) name() string {
	return p.name_
}

// world is the world this PlayerRef's membership generation belongs to, not
// necessarily the player's current world if they've since switched.
pub fn (p PlayerRef) world() World {
	return p.world_
}

// exec runs "f"unction against this player on the actor that owns it and blocks until
// it has run. This is the way to act on a player: everything a player can do
// is a method on player.Player and those take the transaction "f" is handed.
//
// label names the operation in WorldMetrics.longest_task_name.
//
// It fails if the player has disconnected or left the world membership this
// PlayerRef was created for or if that world is shutting down.
pub fn (p PlayerRef) exec(label string, f fn (mut tx worldrt.WorldTx, mut pl player.Player)) ! {
	mut wr := p.world_.runtime
	rid := p.runtime_id
	epoch := p.epoch
	ran := worldrt.world_call[bool](label, mut wr, fn [f, rid, epoch] (mut tx worldrt.WorldTx) bool {
		mut s := player_for_epoch(mut tx, rid, epoch) or { return false }
		f(mut tx, mut s.player)
		return true
	}) or { return error('world "${p.world_.name()}" is shutting down') }
	if !ran {
		return stale_error()
	}
}

// stale_error is what every operation reports when the reference no longer
// names a player in the world it was created for.
fn stale_error() IError {
	return error('player is no longer in this world')
}

// position is the player's current position. Fails if the player has
// disconnected or left the world membership this PlayerRef was created for.
pub fn (p PlayerRef) position() !types.Vector3 {
	mut s := p.resolve()!
	return s.position()
}

// send_message shows message in the player's chat. Same failure mode as
// position. It goes straight to the player rather than through the world
// actor: the verb touches no world state.
pub fn (p PlayerRef) send_message(message string) ! {
	mut s := p.resolve()!
	s.player.send_message(message)
}

// teleport moves the player within their current world. Same failure mode as
// position. It is exec plus Player.teleport, kept because moving a player is
// common enough to be worth one call.
pub fn (p PlayerRef) teleport(pos types.Vector3) ! {
	p.exec('PlayerRef.teleport', fn [pos] (mut tx worldrt.WorldTx, mut pl player.Player) {
		pl.teleport(mut tx, pos)
	})!
}

// teleport_to moves the player into world w at pos, transferring world
// membership. Same failure mode as position.
pub fn (p PlayerRef) teleport_to(w World, pos types.Vector3) ! {
	mut s := p.resolve()!
	s.teleport_to_world(w.name(), pos.x, pos.y, pos.z)
}

// give_item adds count of the item named id to the player's inventory.
// Fails if the player is gone (see position) or id names nothing the server
// knows. The item lands on the world actor; this returns once it has.
pub fn (p PlayerRef) give_item(id string, count int) ! {
	mut s := p.resolve()!
	if !s.give_item(id, count) {
		return error('could not give item "${id}"')
	}
}

// game_mode returns the player's current game mode.
pub fn (p PlayerRef) game_mode() !player.Gamemode {
	mut s := p.resolve()!
	return s.player.game_mode()
}

// set_gamemode changes the player's game mode. Same failure mode as
// position.
pub fn (p PlayerRef) set_gamemode(mode player.Gamemode) ! {
	mut s := p.resolve()!
	s.set_gamemode(mode)
}

// disconnect kicks the player with message shown as the reason. Same
// failure mode as position.
pub fn (p PlayerRef) disconnect(message string) ! {
	mut s := p.resolve()!
	s.disconnect(message)
}
