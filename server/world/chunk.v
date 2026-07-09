module world

pub const dimension_min_y = -64
pub const dimension_subchunk_count = 24
pub const plains_biome_id = 1

pub struct Chunk {
mut:
	sections [][]int
}

pub fn new_chunk() Chunk {
	return Chunk{
		sections: [][]int{len: dimension_subchunk_count}
	}
}

pub fn (mut c Chunk) set_block(x int, y int, z int, b Block) {
	section_index := (y - dimension_min_y) / 16
	if section_index < 0 || section_index >= dimension_subchunk_count {
		return
	}
	if c.sections[section_index].len == 0 {
		c.sections[section_index] = []int{len: 4096, init: air.network_id}
	}
	local_y := (y - dimension_min_y) % 16
	c.sections[section_index][block_index(x, local_y, z)] = b.network_id
}

fn block_index(x int, y int, z int) int {
	return (x << 8) | (z << 4) | y
}

pub fn (c &Chunk) section_count() int {
	for index := dimension_subchunk_count - 1; index >= 0; index-- {
		if c.sections[index].len != 0 {
			return index + 1
		}
	}
	return 0
}

pub fn (c &Chunk) serialize() []u8 {
	mut out := []u8{}
	count := c.section_count()
	for index in 0 .. count {
		out << serialize_section(c.sections[index])
	}
	biome := encode_paletted_storage([]u16{}, [plains_biome_id])
	for _ in 0 .. dimension_subchunk_count {
		out << biome
	}
	out << 0x00
	return out
}

fn serialize_section(ids []int) []u8 {
	mut out := [u8(8), u8(1)]
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
