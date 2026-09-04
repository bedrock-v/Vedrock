module player

import bedrock_v.protocol.types
import server.effect
import server.entity
import server.worldrt

// Viewer is anything that can be shown what a player did.
//
// It speaks in events rather than packets: a verb reports what happened and
// the viewer decides what that looks like on the wire. That is the whole point
// of the interface and the reason a player will eventually stop knowing the
// Bedrock wire format at all.
//
// It embeds entity.Viewer because the same sessions are still reached by
// broadcast_world elsewhere and both paths have to name the same thing while
// the two coexist.
pub interface Viewer {
	entity.Viewer
mut:
	// view_teleport shows "p"layer arriving at pos under its own power or otherwise.
	// Its own client is told to snap; everyone else is told where the body
	// went.
	view_teleport(p &Player, pos types.Vector3)
	// view_movement shows "p"layer at wherever it now is, for a move the client
	// already reported and doesn't need told back.
	view_movement(p &Player)
	// view_hurt shows "p"layer taking damage, without saying from what.
	view_hurt(p &Player)
	// view_death shows "p"layer dying and announces it.
	// message_key/parameters are the localised broadcast.
	view_death(p &Player, message_key string, parameters []string)
	view_effect_added(p &Player, e effect.Effect)
	view_effect_removed(p &Player, typ effect.Type)
	// view_player_added and view_player_removed put a player into the
	// viewer's world and take them back out: the list entry they are
	// attributed by and the body they are drawn as.
	view_player_added(p &Player)
	view_player_removed(p &Player)
	// view_player_respawned puts the body back after a death took it away
	// without touching the list entry, which never left.
	view_player_respawned(p &Player)
	// view_equipment shows what "p"layer is now holding.
	view_equipment(p &Player, hotbar_slot int, inventory_slot int, item types.ItemStackWrapper)
	// view_air_supply is the bubble bar which other clients render too.
	view_air_supply(p &Player, air i64)
}

// viewers is everyone who should be shown what this player does, the player
// included. It is the world's registered players.
//
// Call it on the world actor: it reads the actor owned registry.
pub fn (p &Player) viewers(mut tx worldrt.WorldTx) []Viewer {
	mut out := []Viewer{cap: 4}
	for mut v in tx.wr.viewers() {
		if mut v is Viewer {
			out << v
		}
	}
	return out
}

// runtime_id is the id this player is known by inside the server.
pub fn (p &Player) runtime_id() u64 {
	return p.runtime_id
}
