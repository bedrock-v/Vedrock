module network

import time
import bedrock_v.nbt
import bedrock_v.protocol
import bedrock_v.protocol.enums
import bedrock_v.protocol.packets
import bedrock_v.protocol.serializer
import bedrock_v.protocol.types

// GameData is what a client is told about itself and the world it joins.
pub struct GameData {
pub:
	// entity_id is the player's own entity as both its unique and its runtime
	// id. The client names it back when it has spawned.
	entity_id  u64
	world_name string
	timeout time.Duration = 30 * time.second
}

// start_game spawns a client that has logged in and returns once the client
// says it is in the world. It closes the connection when the deadline passes
// first which ends any read the sequence is blocked on.
pub fn start_game(mut c Conn, data GameData) ! {
	if data.timeout <= 0 {
		return spawn_sequence(mut c, data)
	}
	finished := chan bool{cap: 1}
	sequence := spawn run_spawn_sequence(mut c, data, finished)
	deadline := data.timeout
	select {
		_ := <-finished {}
		deadline {
			c.close()
			sequence.wait() or {}
			return error('did not spawn within ${deadline}')
		}
	}
	sequence.wait()!
}

fn run_spawn_sequence(mut c Conn, data GameData, finished chan bool) ! {
	defer {
		finished <- true
	}
	spawn_sequence(mut c, data)!
}

// spawn_sequence sends the level, then waits for the client to ask for a chunk
// radius, tells it to spawn and waits for it to say it has.
fn spawn_sequence(mut c Conn, data GameData) ! {
	c.write_batch([
		protocol.Packet(jigsaw_structure_data()),
		// Empty: the client keeps its own copy of the vanilla shapes.
		protocol.Packet(&packets.VoxelShapesPacket{}),
		protocol.Packet(start_game_packet(data)),
		protocol.Packet(&packets.ItemComponentPacket{}),
		// The client resolves its own player against this list.
		protocol.Packet(&packets.AvailableActorIdentifiersPacket{
			actor_info_list: actor_identifiers(['minecraft:player'])
		}),
	])!

	requested := c.read_until_chunk_radius()!
	radius := if requested < 1 || requested > max_chunk_radius {
		max_chunk_radius
	} else {
		requested
	}
	c.write_batch([
		protocol.Packet(&packets.ChunkRadiusUpdatedPacket{
			chunk_radius: radius
		}),
		protocol.Packet(&packets.NetworkChunkPublisherUpdatePacket{
			new_view_position: types.BlockPos{
				x: i32(empty_world_spawn[0])
				y: i32(empty_world_spawn[1])
				z: i32(empty_world_spawn[2])
			}
			new_view_radius:   u32(radius * 16)
		}),
		protocol.Packet(&packets.PlayStatusPacket{
			status: .player_spawn
		}),
		protocol.Packet(&packets.CreativeContentPacket{}),
	])!
	send_empty_chunks(mut c, radius)!

	for {
		p := c.read()!
		if p is packets.SetLocalPlayerAsInitializedPacket {
			if p.player_id.value != data.entity_id {
				return error('client spawned as entity ${p.player_id.value}, not ${data.entity_id}')
			}
			return
		}
	}
}

// read_until_chunk_radius reads up to the client's RequestChunkRadius and
// returns the radius it asked for.
fn (mut c Conn) read_until_chunk_radius() !int {
	for {
		p := c.read()!
		if p is packets.RequestChunkRadiusPacket {
			return int(p.chunk_radius)
		}
	}
	return 0
}

fn start_game_packet(data GameData) &packets.StartGamePacket {
	return &packets.StartGamePacket{
		target_actor_id:               types.ActorUniqueID{
			value: i64(data.entity_id)
		}
		target_runtime_id:             types.ActorRuntimeID{
			value: data.entity_id
		}
		actor_game_type:               empty_world_game_type
		position:                      empty_world_spawn
		settings:                      types.LevelSettings{
			generator_type:               .overworld
			game_type:                    empty_world_game_type
			game_difficulty:              .normal
			default_spawn_block_position: types.NetworkBlockPosition{
				x: i32(empty_world_spawn[0])
				y: i32(empty_world_spawn[1])
				z: i32(empty_world_spawn[2])
			}
			multiplayer_enabled:          true
			commands_enabled:             true
			player_permissions:           u8(enums.PlayerPermissionLevel.member)
			server_chunk_tick_range:      max_chunk_radius
			base_game_version:            types.BaseGameVersion{
				value: protocol.minecraft_version
			}
		}
		level_id:                      data.world_name
		level_name:                    data.world_name
		movement_settings:             types.SyncedPlayerMovementSettings{
			server_authoritative_block_breaking: true
		}
		multiplayer_correlation_id:    '00000000-0000-0000-0000-000000000000'
		enable_item_stack_net_manager: true
		server_version:                protocol.minecraft_version
		player_property_data:          empty_compound()
		block_network_ids_are_hashes:  true
	}
}

// jigsaw_structure_data tells the client there are no jigsaw structures.
// It still needs the four lists, each empty.
fn jigsaw_structure_data() &packets.JigsawStructureDataPacket {
	mut root := nbt.new_compound()
	for key in ['processors', 'template_pools', 'jigsaws', 'structure_sets'] {
		root.set(key, nbt.Tag(nbt.List{
			element_type: nbt.tag_compound
		}))
	}
	return &packets.JigsawStructureDataPacket{
		jigsaw_structure_data_tag: nbt.RootTag{
			tag: nbt.Tag(root)
		}
	}
}

fn actor_identifiers(ids []string) nbt.RootTag {
	mut list := []nbt.Tag{cap: ids.len}
	for id in ids {
		mut entry := nbt.new_compound()
		entry.set('id', nbt.Tag(id))
		list << nbt.Tag(entry)
	}
	mut root := nbt.new_compound()
	root.set('idlist', nbt.Tag(nbt.List{
		element_type: nbt.tag_compound
		values:       list
	}))
	return nbt.RootTag{
		tag: nbt.Tag(root)
	}
}

fn empty_compound() nbt.RootTag {
	return nbt.RootTag{
		tag: nbt.Tag(nbt.new_compound())
	}
}

// max_chunk_radius is the most chunks around the player sent in each direction.
const max_chunk_radius = 8

// Everything from here down stands in for a world until the world owns its
// chunks.
const empty_world_spawn = [f32(0.5), 100, 0.5]!
const empty_world_game_type = enums.GameType.creative

// empty_chunk is an overworld chunk with no sub chunks.
fn empty_chunk() []u8 {
	mut w := serializer.new_writer()
	w.u8(0 << 1 | 1)
	w.write_varint32(0)
	for _ in 1 .. 24 {
		w.u8(0x7f << 1 | 1)
	}
	w.u8(0)
	return w.bytes()
}

// send_empty_chunks sends every chunk within radius of the spawn.
fn send_empty_chunks(mut c Conn, radius int) ! {
	cx := int(empty_world_spawn[0]) >> 4
	cz := int(empty_world_spawn[2]) >> 4
	payload := empty_chunk()
	mut batch := []protocol.Packet{}
	for x in cx - radius .. cx + radius + 1 {
		for z in cz - radius .. cz + radius + 1 {
			if (x - cx) * (x - cx) + (z - cz) * (z - cz) > radius * radius {
				continue
			}
			batch << &packets.LevelChunkPacket{
				chunk_position:        types.ChunkPos{
					x: i32(x)
					z: i32(z)
				}
				serialized_chunk_data: payload
			}
			if batch.len == 64 {
				c.write_batch(batch)!
				batch = []protocol.Packet{}
			}
		}
	}
	if batch.len > 0 {
		c.write_batch(batch)!
	}
}
