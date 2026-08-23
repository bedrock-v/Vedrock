module world

pub const dimension_min_y = -64
pub const dimension_subchunk_count = 24
pub const dimension_max_y = dimension_min_y + dimension_subchunk_count * 16 - 1
pub const plains_biome_id = 1

// Section is one 16x16x16 subchunk: a palette of the distinct block ids it
// contains, plus one index per block.
//
// Storing a full network id per block cost 16kB per section - about 105kB for a
// terrain column, all of it churned through the collector on every generation.
// Terrain uses a handful of distinct blocks per subchunk, so a byte index
// covers it; a section that somehow needs more than 256 widens rather than
// capping its palette.
struct Section {
mut:
	palette []int
	narrow  []u8
	wide    []u16
}

fn new_section() Section {
	return Section{
		palette: [air.network_id]
		narrow:  []u8{len: 4096}
	}
}

fn (s &Section) is_empty() bool {
	return s.palette.len == 0
}

fn (s &Section) at(index int) int {
	if s.palette.len == 0 {
		return air.network_id
	}
	if s.wide.len > 0 {
		return s.palette[s.wide[index]]
	}
	return s.palette[s.narrow[index]]
}

fn (mut s Section) set(index int, id int) {
	slot := s.palette_index(id)
	if s.wide.len > 0 {
		s.wide[index] = slot
		return
	}
	s.narrow[index] = u8(slot)
}

// palette_index returns id's palette slot, adding it on first use. The palette
// stays small enough that a scan beats the per section map a lookup table would
// cost.
fn (mut s Section) palette_index(id int) u16 {
	for i, entry in s.palette {
		if entry == id {
			return u16(i)
		}
	}
	s.palette << id
	if s.palette.len > 256 && s.wide.len == 0 {
		s.widen()
	}
	return u16(s.palette.len - 1)
}

// widen switches the section to 16 bit indices, once a byte can no longer
// address its palette.
fn (mut s Section) widen() {
	mut wide := []u16{len: s.narrow.len}
	for i, value in s.narrow {
		wide[i] = u16(value)
	}
	s.wide = wide
	s.narrow = []u8{}
}

fn (s &Section) bytes() i64 {
	return i64(s.palette.len) * i64(sizeof(int)) + i64(s.narrow.len) + i64(s.wide.len) * 2
}

fn (s &Section) clone() Section {
	return Section{
		palette: s.palette.clone()
		narrow:  s.narrow.clone()
		wide:    s.wide.clone()
	}
}

pub struct Chunk {
mut:
	sections       []Section
	min_y          int   = dimension_min_y
	subchunk_count int   = dimension_subchunk_count
	biomes         []int = []int{len: 256, init: plains_biome_id}
}

pub fn new_chunk() Chunk {
	return Chunk{
		sections: []Section{len: dimension_subchunk_count}
	}
}

// new_chunk_dim builds an empty Chunk sized for dim's height range.
pub fn new_chunk_dim(dim Dimension) Chunk {
	return Chunk{
		sections:       []Section{len: dim.subchunk_count}
		min_y:          dim.min_y
		subchunk_count: dim.subchunk_count
	}
}

pub fn (c &Chunk) estimated_bytes() i64 {
	mut total := i64(c.biomes.len) * i64(sizeof(int))
	for section in c.sections {
		total += section.bytes()
	}
	return total
}

pub fn (c &Chunk) clone() Chunk {
	mut sections := []Section{len: c.sections.len}
	for i, section in c.sections {
		sections[i] = section.clone()
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
	return serialize_section(&c.sections[local_index], abs_index)
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
	// Check y before division because V truncates negative integer division
	// toward zero. Values just below min_y could otherwise select section 0
	// and later wrap a negative local index when converted to u32.
	if y < c.min_y {
		return
	}
	section_index := (y - c.min_y) / 16
	if section_index < 0 || section_index >= c.subchunk_count {
		return
	}
	if c.sections[section_index].is_empty() {
		c.sections[section_index] = new_section()
	}
	local_y := (y - c.min_y) % 16
	c.sections[section_index].set(block_index(x, local_y, z), b.network_id)
}

fn block_index(x int, y int, z int) int {
	return int((u32(x) << 8) | (u32(z) << 4) | u32(y))
}

pub fn (mut c Chunk) set_section(index int, ids []int) {
	if index < 0 || index >= c.subchunk_count || ids.len != 4096 {
		return
	}
	mut section := new_section()
	for i, id in ids {
		section.set(i, id)
	}
	c.sections[index] = section
}

pub fn (c &Chunk) block_id(x int, y int, z int) int {
	if y < c.min_y {
		return air.network_id
	}
	section_index := (y - c.min_y) / 16
	if section_index < 0 || section_index >= c.subchunk_count {
		return air.network_id
	}
	if c.sections[section_index].is_empty() {
		return air.network_id
	}
	local_y := (y - c.min_y) % 16
	return c.sections[section_index].at(block_index(x, local_y, z))
}

pub fn (c &Chunk) height_map() []int {
	mut heights := []int{len: 256, init: c.min_y - 1}
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			mut found := false
			for section := c.subchunk_count - 1; section >= 0; section-- {
				if c.sections[section].is_empty() {
					continue
				}
				for local_y := 15; local_y >= 0; local_y-- {
					if c.sections[section].at(block_index(x, local_y, z)) != air.network_id {
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
		if !c.sections[index].is_empty() {
			return index + 1
		}
	}
	return 0
}

// tight returns a copy of b sized exactly to its length.
//
// An array grown by appending keeps whatever capacity the doubling left it
// with, so a ~10kB serialized column sits in a 16kB block - and clone()
// preserves the capacity rather than shedding it. The chunk cache holds one of
// these per column, where that slack was a third of its real cost.
fn tight(b []u8) []u8 {
	mut out := []u8{len: b.len}
	copy(mut out, b)
	return out
}

pub fn (c &Chunk) serialize() []u8 {
	mut out := []u8{}
	count := c.section_count()
	base_index := c.min_y / 16
	for index in 0 .. count {
		out << serialize_section(&c.sections[index], base_index + index)
	}
	biome := c.serialize_biomes()
	for _ in 0 .. c.subchunk_count {
		out << biome
	}
	out << 0x00
	return tight(out)
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

fn serialize_section(section &Section, abs_index int) []u8 {
	mut out := [u8(9), u8(1), u8(i8(abs_index))]
	if section.is_empty() {
		out << encode_paletted_storage([]u16{}, [air.network_id])
		return out
	}
	out << encode_section_storage(section.palette, section.narrow, section.wide)
	return out
}
