module network

import compress.gzip
import bedrock_v.nbt
import bedrock_v.protocol.packets
import bedrock_v.protocol.types

// vanilla_block_properties are the vanilla blocks defined by their components
// instead of built into the client.
const vanilla_block_properties = block_properties($embed_file('block_definitions.nbt').to_bytes()) or {
	panic('network: the embedded block definitions: ${err}')
}

// vanilla_biomes is the biome list a client needs to make sense of the biomes
// in chunks.
const vanilla_biomes = biome_definitions($embed_file('biome_definitions.nbt').to_bytes()) or {
	panic('network: the embedded biome definitions: ${err}')
}

// block_properties reads a list of blocks, each a name and the compound of
// its properties that the client takes as it is.
fn block_properties(gzipped []u8) ![]packets.BlockProperty {
	root := read_big_endian(gzipped)!
	mut out := []packets.BlockProperty{}
	for entry in list_of(root, 'blocks')! {
		name := entry.get('name') or { return error('a block has no name') }
		properties := entry.get('properties') or { return error('${name} has no properties') }
		if name !is string || properties !is nbt.Compound {
			return error('a block is not a name and properties')
		}
		out << packets.BlockProperty{
			block_name:       name as string
			block_definition: nbt.RootTag{
				tag: properties
			}
		}
	}
	return out
}

// biome_definitions reads the biome list into the packet that carries it.
fn biome_definitions(gzipped []u8) !&packets.BiomeDefinitionListPacket {
	root := read_big_endian(gzipped)!
	strings_tag := root.get('biomeStringList') or { return error('there is no string list') }
	if strings_tag !is nbt.List {
		return error('the string list is not a list')
	}
	mut strings := []string{}
	for s in (strings_tag as nbt.List).values {
		if s !is string {
			return error('the string list holds something other than strings')
		}
		strings << s as string
	}
	mut biomes := []packets.BiomeEntry{}
	for entry in list_of(root, 'biomeData')! {
		data := compound(entry, 'data')!
		name_index := u16(number(entry, 'index')!)
		if name_index >= strings.len {
			return error('a biome is named by string ${name_index} of ${strings.len}')
		}
		mut tags := ?types.BiomeTagList(none)
		if holder := entry_compound(data, 'tags') {
			list := holder.get('tags') or { nbt.Tag(nbt.List{}) }
			if list !is nbt.List {
				return error('the tags of biome ${strings[name_index]} are not a list')
			}
			mut indices := []u16{}
			for t in (list as nbt.List).values {
				if t !is i16 || u16(t as i16) >= strings.len {
					return error('biome ${strings[name_index]} has a tag that is not a string index')
				}
				indices << u16(t as i16)
			}
			tags = types.BiomeTagList{indices}
		}
		biomes << packets.BiomeEntry{
			name_index: name_index
			definition: types.BiomeDefinition{
				id:              u16(number(data, 'id')!)
				temperature:     decimal(data, 'temperature')!
				downfall:        decimal(data, 'downfall')!
				foliage_snow:    decimal(data, 'foliageSnow')!
				depth:           decimal(data, 'depth')!
				scale:           decimal(data, 'scale')!
				map_water_color: i32(number(data, 'mapWaterColorARGB')!)
				rain:            number(data, 'rain')! != 0
				tags:            tags
			}
		}
	}
	return &packets.BiomeDefinitionListPacket{
		biomes:  biomes
		strings: strings
	}
}

fn read_big_endian(gzipped []u8) !nbt.Compound {
	tag := nbt.decode(gzip.decompress(gzipped)!, encoding: .big_endian)!.root.tag
	if tag !is nbt.Compound {
		return error('the root is not a compound')
	}
	return tag as nbt.Compound
}

fn list_of(c nbt.Compound, key string) ![]nbt.Compound {
	tag := c.get(key) or { return error('there is no ${key}') }
	if tag !is nbt.List {
		return error('${key} is not a list')
	}
	mut out := []nbt.Compound{}
	for value in (tag as nbt.List).values {
		if value !is nbt.Compound {
			return error('${key} holds something other than compounds')
		}
		out << value as nbt.Compound
	}
	return out
}

fn entry_compound(c nbt.Compound, key string) ?nbt.Compound {
	tag := c.get(key)?
	if tag is nbt.Compound {
		return tag
	}
	return none
}

fn compound(c nbt.Compound, key string) !nbt.Compound {
	return entry_compound(c, key) or { return error('${key} is not a compound') }
}

fn number(c nbt.Compound, key string) !i64 {
	tag := c.get(key) or { return error('there is no ${key}') }
	return match tag {
		i8 { i64(tag) }
		i16 { i64(tag) }
		i32 { i64(tag) }
		i64 { tag }
		else { error('${key} is not a whole number') }
	}
}

fn decimal(c nbt.Compound, key string) !f32 {
	tag := c.get(key) or { return error('there is no ${key}') }
	if tag !is f32 {
		return error('${key} is not a float')
	}
	return tag as f32
}
