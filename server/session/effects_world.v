module session

import bedrock_v.protocol.types
import server.entity
import server.world.particle
import server.world.sound
import server.worldrt

// play_sound plays snd at pos for every session in this transaction's world.
fn play_sound(mut tx worldrt.WorldTx, pos types.Vector3, snd sound.Sound) {
	for mut v in tx.wr.viewers() {
		v.view_sound(pos, snd, entity.SoundSource{})
	}
}

// play_actor_sound plays a sound the client renders as coming from an actor,
// naming that actor so it can pick the variation that belongs to it.
fn play_actor_sound(mut tx worldrt.WorldTx, pos types.Vector3, snd sound.Sound, source entity.SoundSource) {
	for mut v in tx.wr.viewers() {
		v.view_sound(pos, snd, source)
	}
}

// play_sound_except plays snd for every session in this transaction's world
// but the one that caused it, which normally renders the sound itself.
fn play_sound_except(mut tx worldrt.WorldTx, except_runtime_id u64, pos types.Vector3, snd sound.Sound) {
	for mut v in tx.wr.viewers_except(except_runtime_id) {
		v.view_sound(pos, snd, entity.SoundSource{})
	}
}

// add_particle shows p at pos for every session in this transaction's world.
fn add_particle(mut tx worldrt.WorldTx, pos types.Vector3, p particle.Particle) {
	for mut v in tx.wr.viewers() {
		v.view_particle(pos, p)
	}
}

// play_sound plays snd at the player's own position, for that player only.
fn (mut s NetworkSession) play_sound(snd sound.Sound) {
	s.view_sound(s.current_position(), snd, entity.SoundSource{})
}
