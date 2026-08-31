module session

import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import server.world.particle
import server.world.sound

// play_sound plays snd at pos for every session in this transaction's world.
fn (mut tx WorldTx) play_sound(pos types.Vector3, snd sound.Sound) {
	tx.wr.broadcast_world(proto.level_sound_event(snd.event_name(), pos, snd.data(), '', 0))
}

// play_sound_except plays snd for every session in this transaction's world
// but the one that caused it, which normally renders the sound itself.
fn (mut tx WorldTx) play_sound_except(except_runtime_id u64, pos types.Vector3, snd sound.Sound) {
	tx.wr.broadcast_world_except(except_runtime_id, proto.level_sound_event(snd.event_name(), pos,
		snd.data(), '', 0))
}

// add_particle shows p at pos for every session in this transaction's world.
fn (mut tx WorldTx) add_particle(pos types.Vector3, p particle.Particle) {
	mut packet := &proto.LevelEventPacket{
		event_id: p.event_id()
		data:     p.data()
	}
	packet.position[0] = pos.x
	packet.position[1] = pos.y
	packet.position[2] = pos.z
	tx.wr.broadcast_world(packet)
}

// play_sound plays snd at the player's own position, for that player only.
fn (mut s NetworkSession) play_sound(snd sound.Sound) {
	s.deliver(proto.level_sound_event(snd.event_name(), s.current_position(), snd.data(), '', 0))
}
