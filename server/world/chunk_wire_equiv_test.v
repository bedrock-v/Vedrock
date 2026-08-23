module world

// Decodes a serialized column the way the client reads it and checks every
// block against the chunk it came from. The section palette is built as blocks
// are written, so its entry order is not the order a position scan would
// produce - this pins the thing that actually matters, which is that the wire
// bytes describe the same world.

struct SectionView {
	bits    u8
	palette []int
	words   []u32
}

fn (v &SectionView) block(index int) int {
	if v.bits == 0 {
		return v.palette[0]
	}
	per_word := 32 / int(v.bits)
	word := v.words[index / per_word]
	shift := u32((index % per_word) * int(v.bits))
	mask := u32((u64(1) << v.bits) - 1)
	return v.palette[(word >> shift) & mask]
}

struct WireCursor {
	data []u8
mut:
	pos int
}

fn (mut c WireCursor) u8() u8 {
	v := c.data[c.pos]
	c.pos++
	return v
}

fn (mut c WireCursor) u32_le() u32 {
	v := u32(c.data[c.pos]) | (u32(c.data[c.pos + 1]) << 8) | (u32(c.data[c.pos + 2]) << 16) | (u32(c.data[c.pos + 3]) << 24)
	c.pos += 4
	return v
}

fn (mut c WireCursor) varint_signed() int {
	mut shift := u32(0)
	mut acc := u32(0)
	for {
		b := c.u8()
		acc |= u32(b & 0x7f) << shift
		if b & 0x80 == 0 {
			break
		}
		shift += 7
	}
	return int((acc >> 1) ^ (-(acc & 1)))
}

fn (mut c WireCursor) storage() SectionView {
	head := c.u8()
	bits := head >> 1
	mut words := []u32{}
	mut palette_size := 1
	if bits > 0 {
		per_word := 32 / int(bits)
		for _ in 0 .. (4096 + per_word - 1) / per_word {
			words << c.u32_le()
		}
		palette_size = c.varint_signed()
	}
	mut palette := []int{cap: palette_size}
	for _ in 0 .. palette_size {
		palette << c.varint_signed()
	}
	return SectionView{
		bits:    bits
		palette: palette
		words:   words
	}
}

fn decode_sections(data []u8, count int) []SectionView {
	mut c := WireCursor{
		data: data
	}
	mut views := []SectionView{cap: count}
	for _ in 0 .. count {
		c.u8() // version
		storages := c.u8()
		c.u8() // absolute y index
		mut first := SectionView{}
		for i in 0 .. storages {
			view := c.storage()
			if i == 0 {
				first = view
			}
		}
		views << first
	}
	return views
}

fn assert_wire_matches(chunk Chunk) {
	views := decode_sections(chunk.serialize(), chunk.section_count())
	for section, view in views {
		for x in 0 .. 16 {
			for z in 0 .. 16 {
				for y in 0 .. 16 {
					want := chunk.block_id(x, chunk.min_y + section * 16 + y, z)
					got := view.block(block_index(x, y, z))
					assert got == want, 'section ${section} (${x}, ${y}, ${z}): wire ${got} != chunk ${want}'
				}
			}
		}
	}
}

fn test_serialized_generated_columns_describe_the_same_blocks() {
	gen := NormalGenerator{}
	for cx in -2 .. 3 {
		for cz in -2 .. 3 {
			assert_wire_matches(gen.generate(cx, cz))
		}
	}
}

fn test_serialized_flat_and_edited_columns_describe_the_same_blocks() {
	flat := FlatGenerator{}
	assert_wire_matches(flat.generate(0, 0))

	mut edited := new_chunk()
	edited.set_block(0, -64, 0, bedrock)
	edited.set_block(5, 12, 9, stone)
	edited.set_block(15, 200, 15, stone)
	assert_wire_matches(edited)
}

// A section that outgrows a byte index has to widen without losing blocks.
fn test_section_widens_past_a_byte_palette() {
	mut section := new_section()
	for i in 0 .. 300 {
		section.set(i, 1000 + i)
	}
	assert section.wide.len == 4096
	assert section.narrow.len == 0
	for i in 0 .. 300 {
		assert section.at(i) == 1000 + i
	}
	assert section.at(300) == air.network_id
}
