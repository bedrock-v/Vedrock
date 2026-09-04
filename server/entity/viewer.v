module entity

import bedrock_v.protocol
import server.effect

// Viewer is anything that can be shown what happens in a world.
//
// Like player.Viewer it speaks in events rather than packets, this package
// says what an entity did and the session decides what that looks like on the
// wire. It exists here rather than in session so world level code can reach the
// clients in a world without naming the layer that owns connections.
pub interface Viewer {
	runtime_id() u64
mut:
	deliver(p protocol.Packet)
	// view_entity_spawn and view_entity_despawn put an entity into the
	// viewer's world and take it back out again.
	view_entity_spawn(e &Entity)
	view_entity_despawn(e &Entity)
	// view_entity_movement shows the entity at wherever it now is.
	view_entity_movement(e &Entity)
	// view_entity_health and view_entity_hurt are the health bar's value and
	// the flinch that goes with losing some of it.
	view_entity_health(e &Entity)
	view_entity_hurt(e &Entity)
	view_entity_effect_added(e &Entity, ef effect.Effect)
	view_entity_effect_removed(e &Entity, typ effect.Type)
	// The three below name an actor by its internal id rather than by type
	// because the thing that happened is the same whether a player or a mob
	// did it. The viewer maps the id to its own numbering.
	view_actor_swing(actor u64)
	view_actor_critical_hit(actor u64)
	view_item_taken(item u64, taker u64)
}

// player_viewers returns every registered player actor that can be shown
// something. Registered mob entities are not viewers and are left out.
pub fn (mut m Manager) player_viewers() []Viewer {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	mut list := []Viewer{cap: m.actors.len}
	for _, entry in m.actors {
		if entry.actor is Entity {
			continue
		}
		mut a := entry.actor
		if mut a is Viewer {
			list << a
		}
	}
	return list
}
