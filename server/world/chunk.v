module world

pub const dimension_min_y = -64
pub const dimension_subchunk_count = 24
pub const dimension_max_y = dimension_min_y + dimension_subchunk_count * 16 - 1
pub const plains_biome_id = 1

pub struct Chunk {
mut:
	sections       [][]int
	min_y          int   = dimension_min_y
	subchunk_count int   = dimension_subchunk_count
	biomes         []int = []int{len: 256, init: plains_biome_id}
}

pub fn new_chunk() Chunk {
	return Chunk{
		sections: [][]int{len: dimension_subchunk_count}
	}
}

// new_chunk_dim builds an empty Chunk sized for dim's height range.
pub fn new_chunk_dim(dim Dimension) Chunk {
	return Chunk{
		sections:       [][]int{len: dim.subchunk_count}
		min_y:          dim.min_y
		subchunk_count: dim.subchunk_count
	}
}

pub fn (c &Chunk) clone() Chunk {
	mut sections := [][]int{len: c.sections.len}
	for i, ids in c.sections {
		sections[i] = ids.clone()
	}
	return Chunk{
		sections:       sections
		min_y:          c.min_y
		subchunk_count: c.subchunk_count
		biomes:         c.biomes.clone()
	}
}

// serialize_subchunk encodes a single subchunk (as used by SubChunkPacket
// responses to a SubChunkRequestPacket), addressed by its absolute Y index
// (block Y / 16 - e.g. -4 for the overworld's bottom section). Returns none
// if abs_index falls outside this chunk's height range.
pub fn (c &Chunk) serialize_subchunk(abs_index int) ?[]u8 {
	local_index := abs_index - c.min_y / 16
	if local_index < 0 || local_index >= c.subchunk_count {
		return none
	}
	return serialize_section(c.sections[local_index], abs_index)
}

// set_biome assigns the biome id for column (x, z), applied to the full
// height of the chunk.
pub fn (mut c Chunk) set_biome(x int, z int, biome_id int) {
	if x < 0 || x >= 16 || z < 0 || z >= 16 {
		return
	}
	c.biomes[x * 16 + z] = biome_id
}

// biome_id returns the biome id previously set for column (x, z).
pub fn (c &Chunk) biome_id(x int, z int) int {
	if x < 0 || x >= 16 || z < 0 || z >= 16 {
		return plains_biome_id
	}
	return c.biomes[x * 16 + z]
}

pub fn (mut c Chunk) set_block(x int, y int, z int, b Block) {
	section_index := (y - c.min_y) / 16
	if section_index < 0 || section_index >= c.subchunk_count {
		return
	}
	if c.sections[section_index].len == 0 {
		c.sections[section_index] = []int{len: 4096, init: air.network_id}
	}
	local_y := (y - c.min_y) % 16
	c.sections[section_index][block_index(x, local_y, z)] = b.network_id
}

fn block_index(x int, y int, z int) int {
	return int((u32(x) << 8) | (u32(z) << 4) | u32(y))
}

pub fn (mut c Chunk) set_section(index int, ids []int) {
	if index < 0 || index >= c.subchunk_count || ids.len != 4096 {
		return
	}
	c.sections[index] = ids
}

pub fn (c &Chunk) block_id(x int, y int, z int) int {
	section_index := (y - c.min_y) / 16
	if section_index < 0 || section_index >= c.subchunk_count {
		return air.network_id
	}
	if c.sections[section_index].len == 0 {
		return air.network_id
	}
	local_y := (y - c.min_y) % 16
	return c.sections[section_index][block_index(x, local_y, z)]
}

pub fn (c &Chunk) height_map() []int {
	mut heights := []int{len: 256, init: c.min_y - 1}
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			mut found := false
			for section := c.subchunk_count - 1; section >= 0; section-- {
				if c.sections[section].len == 0 {
					continue
				}
				for local_y := 15; local_y >= 0; local_y-- {
					if c.sections[section][block_index(x, local_y, z)] != air.network_id {
						heights[z * 16 + x] = c.min_y + section * 16 + local_y
						found = true
						break
					}
				}
				if found {
					break
				}
			}
		}
	}
	return heights
}

pub fn (c &Chunk) section_count() int {
	for index := c.subchunk_count - 1; index >= 0; index-- {
		if c.sections[index].len != 0 {
			return index + 1
		}
	}
	return 0
}

pub fn (c &Chunk) serialize() []u8 {
	mut out := []u8{}
	count := c.section_count()
	base_index := c.min_y / 16
	for index in 0 .. count {
		out << serialize_section(c.sections[index], base_index + index)
	}
	biome := c.serialize_biomes()
	for _ in 0 .. c.subchunk_count {
		out << biome
	}
	out << 0x00
	return out
}

// serialize_biomes encodes c.biomes (a per-column x/z grid) as one
// PalettedStorage, replicated across every y in a subchunk - same format as
// serialize_section, just varying by (x, z) only, not y.
pub fn (c &Chunk) serialize_biomes() []u8 {
	mut palette := []int{}
	mut lookup := map[int]u16{}
	mut indices := []u16{len: 4096}
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			id := c.biomes[x * 16 + z]
			palette_index := lookup[id] or {
				new_index := u16(palette.len)
				palette << id
				lookup[id] = new_index
				new_index
			}
			for y in 0 .. 16 {
				indices[block_index(x, y, z)] = palette_index
			}
		}
	}
	if palette.len == 1 {
		return encode_paletted_storage([]u16{}, palette)
	}
	return encode_paletted_storage(indices, palette)
}

fn serialize_section(ids []int, abs_index int) []u8 {
	mut out := [u8(9), u8(1), u8(i8(abs_index))]
	if ids.len == 0 {
		out << encode_paletted_storage([]u16{}, [air.network_id])
		return out
	}
	mut palette := []int{}
	mut lookup := map[int]u16{}
	mut indices := []u16{len: 4096}
	for position in 0 .. 4096 {
		id := ids[position]
		indices[position] = lookup[id] or {
			new_index := u16(palette.len)
			palette << id
			lookup[id] = new_index
			new_index
		}
	}
	out << encode_paletted_storage(indices, palette)
	return out
}
