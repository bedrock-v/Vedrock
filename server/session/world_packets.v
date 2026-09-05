module session

import bedrock_v.nbt
import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import server.entity
import server.world.particle
import server.world.sound
import server.worldrt

// This file renders the world level half of entity.Viewer: the events that
// belong to a place rather than to an actor. They are built per viewer for the
// same reason the entity ones are, an actor id means something different to
// every client.

fn (mut s NetworkSession) view_sound(pos types.Vector3, snd sound.Sound, source entity.SoundSource) {
	mut actor := u64(0)
	if source.identifier != '' {
		actor = s.wire_id_for(source.actor)
	}
	s.deliver(proto.level_sound_event(snd.event_name(), pos, snd.data(), source.identifier,
		actor))
}

// broadcast_actor_sound plays snd for every session in the hub, naming its
// source in each recipient's own numbering. One packet per recipient for the
// reason broadcast_armor gives.
fn (mut s NetworkSession) broadcast_actor_sound(pos types.Vector3, snd sound.Sound, source entity.SoundSource) {
	mut hub := s.hub
	for mut target in hub.snapshot() {
		target.view_sound(pos, snd, source)
	}
}

fn (mut s NetworkSession) view_particle(pos types.Vector3, p particle.Particle) {
	mut packet := &proto.LevelEventPacket{
		event_id: p.event_id()
		data:     p.data()
	}
	packet.position[0] = pos.x
	packet.position[1] = pos.y
	packet.position[2] = pos.z
	s.deliver(packet)
}

fn (mut s NetworkSession) view_block_update(pos types.BlockPosition, runtime_id int) {
	s.deliver(&proto.UpdateBlockPacket{
		block_position:   proto.block_pos(pos)
		block_runtime_id: u32(runtime_id)
		flags:            worldrt.block_update_flags
		layer:            0
	})
}

fn (mut s NetworkSession) view_block_entity(pos types.BlockPosition, tags nbt.RootTag) {
	s.deliver(&proto.BlockActorDataPacket{
		block_position:  proto.block_pos(pos)
		actor_data_tags: tags
	})
}

// player_actor_identifier is the actor type a sound made by a player carries.
const player_actor_identifier = 'minecraft:player'
