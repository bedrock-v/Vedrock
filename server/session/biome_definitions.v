module session

import os
import protocol

import server.internal.gamedata
import server.world
import protocol.current as proto

struct BiomeDescriptor {
	id          int
	name        string
	temperature f32
	downfall    f32
	depth       f32
	scale       f32
	rain        bool
}

// vanilla_biome_descriptors covers every biome id server.world's generators
// actually assign to a chunk column (world/biome.v, world/generator.v). A
// real Bedrock client resolves each biome id referenced in the chunk data
// it receives against this list. An id with no matching entry here has
// nothing to resolve against.
const vanilla_biome_descriptors = [
	BiomeDescriptor{
		id:          world.biome_ocean
		name:        'ocean'
		temperature: 0.5
		downfall:    0.5
		depth:       -1.0
		scale:       0.1
		rain:        true
	},
	BiomeDescriptor{
		id:          world.plains_biome_id
		name:        'plains'
		temperature: 0.8
		downfall:    0.4
		depth:       0.1
		scale:       0.05
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_desert
		name:        'desert'
		temperature: 2.0
		downfall:    0.0
		depth:       0.125
		scale:       0.05
		rain:        false
	},
	BiomeDescriptor{
		id:          world.biome_extreme_hills
		name:        'extreme_hills'
		temperature: 0.2
		downfall:    0.3
		depth:       1.0
		scale:       0.5
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_forest
		name:        'forest'
		temperature: 0.7
		downfall:    0.8
		depth:       0.1
		scale:       0.2
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_taiga
		name:        'taiga'
		temperature: 0.25
		downfall:    0.8
		depth:       0.2
		scale:       0.2
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_swampland
		name:        'swampland'
		temperature: 0.8
		downfall:    0.9
		depth:       -0.2
		scale:       0.1
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_river
		name:        'river'
		temperature: 0.5
		downfall:    0.5
		depth:       -0.5
		scale:       0.0
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_ice_plains
		name:        'ice_plains'
		temperature: 0.0
		downfall:    0.5
		depth:       0.125
		scale:       0.05
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_extreme_hills_edge
		name:        'extreme_hills_edge'
		temperature: 0.2
		downfall:    0.3
		depth:       0.8
		scale:       0.3
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_birch_forest
		name:        'birch_forest'
		temperature: 0.6
		downfall:    0.6
		depth:       0.1
		scale:       0.2
		rain:        true
	},
	BiomeDescriptor{
		id:          world.biome_hell
		name:        'hell'
		temperature: 2.0
		downfall:    0.0
		depth:       0.1
		scale:       0.2
		rain:        false
	},
	BiomeDescriptor{
		id:          world.biome_the_end
		name:        'the_end'
		temperature: 0.5
		downfall:    0.5
		depth:       0.1
		scale:       0.2
		rain:        false
	},
	BiomeDescriptor{
		id:          world.biome_snowy_taiga
		name:        'cold_taiga'
		temperature: -0.5
		downfall:    0.4
		depth:       0.2
		scale:       0.2
		rain:        true
	},
]

// Mojang ships the biome registry as an NBT document; the client wants it as
// a packet payload. Encoding it once at startup keeps the registry sourced
// from the shipped data rather than a captured packet dump.
const vanilla_biome_definitions = gamedata.load_biome_definitions(os.join_path('data',
	'biome_definitions.nbt')) or { []u8{} }

const vanilla_biome_definitions_packet = &protocol.RawPacket{
	packet_id: 122
	raw_name:  'BiomeDefinitionListPacket'
	payload:   vanilla_biome_definitions.clone()
}

// biome_definition_list is the biome registry sent to a joining client. An
// empty BiomeDefinitionListPacket leaves the client with no way to resolve
// any biome id present in the chunk/biome data it is about to receive.
fn biome_definition_list() protocol.Packet {
	if vanilla_biome_definitions.len > 0 {
		return vanilla_biome_definitions_packet
	}
	return generated_biome_definition_list()
}

// generated_biome_definition_list is the fallback used when the captured
// registry is missing: it covers the ids the generators actually assign.
fn generated_biome_definition_list() &proto.BiomeDefinitionListPacket {
	mut strings := []string{}
	mut biomes := []proto.BiomeEntry{}
	for d in vanilla_biome_descriptors {
		name_index := u16(strings.len)
		// The client matches these against its own registry, which is
		// namespaced. A bare name resolves to nothing and leaves every biome
		// id in the chunk data it receives next unresolvable.
		strings << 'minecraft:${d.name}'
		biomes << proto.BiomeEntry{
			name_index: name_index
			definition: proto.BiomeDefinition{
				id:              u16(d.id)
				temperature:     d.temperature
				downfall:        d.downfall
				foliage_snow:    0.0
				depth:           d.depth
				scale:           d.scale
				map_water_color: 0x3f76e4
				rain:            d.rain
			}
		}
	}
	return &proto.BiomeDefinitionListPacket{
		biomes:  biomes
		strings: strings
	}
}
