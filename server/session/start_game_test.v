module session

import protocol
import types
import serializer
import nbt

fn roundtrip(p protocol.Packet) !protocol.Packet {
	mut pool := protocol.new_packet_pool()
	encoded := protocol.encode_packet_to_bytes(p)
	mut r := serializer.new_reader(encoded)
	return pool.decode(mut r)!
}

fn test_resource_packs_info_roundtrip() {
	decoded := roundtrip(&protocol.ResourcePacksInfoPacket{
		must_accept: false
		entries:     []protocol.ResourcePackInfoEntry{}
	})!
	assert decoded.name() == 'ResourcePacksInfoPacket'
}

fn test_resource_pack_stack_roundtrip() {
	decoded := roundtrip(&protocol.ResourcePackStackPacket{
		must_accept:         false
		resource_pack_stack: []protocol.ResourcePackStackEntry{}
		base_game_version:   protocol.minecraft_version_network
		experiments:         types.Experiments{}
	})!
	assert decoded.name() == 'ResourcePackStackPacket'
}

fn test_start_game_roundtrip() {
	decoded := roundtrip(&protocol.StartGamePacket{
		entity_unique_id:               1
		entity_runtime_id:              1
		player_game_mode:               1
		player_position:                types.Vector3{0.0, 64.0, 0.0}
		generator:                      1
		difficulty:                     1
		world_spawn:                    types.BlockPosition{0, 64, 0}
		commands_enabled:               true
		multi_player_game:              true
		base_game_version:              protocol.minecraft_version_network
		game_version:                   protocol.minecraft_version_network
		level_id:                       'Vedrock'
		world_name:                     'Vedrock Server'
		multi_player_correlation_id:    '00000000-0000-0000-0000-000000000000'
		server_authoritative_inventory: true
		property_data:                  nbt.RootTag{
			name: ''
			tag:  nbt.Tag(nbt.new_compound())
		}
		blocks:                         []protocol.BlockEntry{}
	})!
	assert decoded.name() == 'StartGamePacket'
	if decoded is protocol.StartGamePacket {
		assert decoded.world_name == 'Vedrock Server'
		assert decoded.game_version == protocol.minecraft_version_network
	} else {
		assert false
	}
}

fn test_registry_packets_roundtrip() {
	assert roundtrip(&protocol.ItemRegistryPacket{
		entries: []types.ItemTypeEntry{}
	})!.name() == 'ItemRegistryPacket'
	assert roundtrip(&protocol.CreativeContentPacket{
		groups: []types.CreativeGroupEntry{}
		items:  []types.CreativeItemEntry{}
	})!.name() == 'CreativeContentPacket'
	assert roundtrip(&protocol.BiomeDefinitionListPacket{
		biome_definitions: []protocol.BiomeDefinition{}
		string_list:       []string{}
	})!.name() == 'BiomeDefinitionListPacket'
}
