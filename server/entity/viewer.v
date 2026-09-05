module entity

import bedrock_v.nbt
import bedrock_v.protocol.types
import server.effect
import server.world.particle
import server.world.sound

// Viewer is anything that can be shown what happens in a world.
//
// Like player.Viewer it speaks in events rather than packets, this package
// says what an entity did and the session decides what that looks like on the
// wire. It exists here rather than in session so world level code can reach the
// clients in a world without naming the layer that owns connections.
pub interface Viewer {
	runtime_id() u64
mut:
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
	// The four below are world events rather than entity ones. They live in
	// this interface because it is the only vocabulary world level code has
	// for reaching the clients that can see a place.
	//
	// view_sound plays snd at pos. source names the actor the sound belongs
	// to; a sound that belongs to nobody passes a zero SoundSource.
	view_sound(pos types.Vector3, snd sound.Sound, source SoundSource)
	view_particle(pos types.Vector3, p particle.Particle)
	// view_block_update shows the block now standing at pos, and
	// view_block_entity the data attached to it for the blocks that carry
	// more state than a runtime id can hold.
	view_block_update(pos types.BlockPosition, runtime_id int)
	view_block_entity(pos types.BlockPosition, tags nbt.RootTag)
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

// SoundSource is the actor a sound came from. The client renders some sound
// events differently depending on what made them, so both halves matter: the
// identifier picks the variation and the actor places it. The actor is named
// in the server's own numbering and translated by whoever is being shown it.
//
// The zero value means the sound came from no actor which is what the wire
// carries for a sound that belongs to a place rather than to something in it.
pub struct SoundSource {
pub:
	actor      u64
	identifier string
}
