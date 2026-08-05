module session

import protocol.version.v1001.packets as packets_1001
import protocol.version.v1001.types as types_1001
import server.world

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
		id:          world.biome_taiga
		name:        'taiga'
		temperature: 0.25
		downfall:    0.8
		depth:       0.2
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
		name:        'ice_plains'
		temperature: -0.5
		downfall:    0.4
		depth:       0.2
		scale:       0.2
		rain:        true
	},
]

// biome_definition_list builds the real biome registry sent to a joining
// client. An empty BiomeDefinitionListPacket leaves the client with no way
// to resolve any biome id present in the chunk/biome data it is about to
// receive.
fn biome_definition_list() &packets_1001.BiomeDefinitionListPacket {
	mut strings := []string{}
	mut biomes := []packets_1001.BiomeEntry{}
	for d in vanilla_biome_descriptors {
		name_index := u16(strings.len)
		strings << d.name
		biomes << packets_1001.BiomeEntry{
			name_index: name_index
			definition: types_1001.BiomeDefinition{
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
	return &packets_1001.BiomeDefinitionListPacket{
		biomes:  biomes
		strings: strings
	}
}
