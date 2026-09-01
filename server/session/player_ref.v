module session

import bedrock_v.protocol.types
import server.player

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

// position is the player's current position. Fails if the player has
// disconnected or left the world membership this PlayerRef was created for.
pub fn (p PlayerRef) position() !types.Vector3 {
	mut s := p.resolve()!
	return s.position()
}

// send_message shows message in the player's chat. Same failure mode as
// position.
pub fn (p PlayerRef) send_message(message string) ! {
	mut s := p.resolve()!
	s.send_message(message)!
}

// teleport moves the player within their current world. Same failure mode
// as position.
pub fn (p PlayerRef) teleport(pos types.Vector3) ! {
	mut s := p.resolve()!
	s.teleport(pos.x, pos.y, pos.z)
}

// teleport_to moves the player into world w at pos, transferring world
// membership. Same failure mode as position.
pub fn (p PlayerRef) teleport_to(w World, pos types.Vector3) ! {
	mut s := p.resolve()!
	s.teleport_to_world(w.name(), pos.x, pos.y, pos.z)
}

// give_item adds count of the item named id to the player's inventory.
// Fails if the player is gone (see position) or their inventory has no room.
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
