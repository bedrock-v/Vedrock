module gamedata

// BlockPaletteEntry is one block state from the wire palette, in file order.
// network_id is the exact FNV1a-32 state hash the client expects, read from
// the palette rather than recomputed, so it can never disagree with vanilla.
pub struct BlockPaletteEntry {
pub:
	name       string
	network_id int
}

struct BeReader {
	data []u8
mut:
	pos int
}

fn (mut r BeReader) u8() !u8 {
	if r.pos >= r.data.len {
		return error('nbt_be: out of bounds')
	}
	value := r.data[r.pos]
	r.pos++
	return value
}

fn (mut r BeReader) skip(n int) ! {
	if n < 0 || r.pos + n > r.data.len {
		return error('nbt_be: skip out of bounds')
	}
	r.pos += n
}

fn (mut r BeReader) i16() !int {
	high := u32(r.u8()!)
	low := u32(r.u8()!)
	return int((high << 8) | low)
}

fn (mut r BeReader) i32() !int {
	mut value := u32(0)
	for _ in 0 .. 4 {
		value = (value << 8) | u32(r.u8()!)
	}
	return int(value)
}

fn (mut r BeReader) read_name() !string {
	length := r.i16()!
	if r.pos + length > r.data.len {
		return error('nbt_be: name out of bounds')
	}
	name := r.data[r.pos..r.pos + length].bytestr()
	r.pos += length
	return name
}

fn (mut r BeReader) skip_payload(tag_type u8) ! {
	match tag_type {
		1 {
			r.skip(1)!
		}
		2 {
			r.skip(2)!
		}
		3 {
			r.skip(4)!
		}
		4 {
			r.skip(8)!
		}
		5 {
			r.skip(4)!
		}
		6 {
			r.skip(8)!
		}
		7 {
			r.skip(r.i32()!)!
		}
		8 {
			r.skip(r.i16()!)!
		}
		9 {
			element_type := r.u8()!
			count := r.i32()!
			for _ in 0 .. count {
				r.skip_payload(element_type)!
			}
		}
		10 {
			for {
				entry_type := r.u8()!
				if entry_type == 0 {
					break
				}
				r.read_name()!
				r.skip_payload(entry_type)!
			}
		}
		11 {
			r.skip(r.i32()! * 4)!
		}
		12 {
			r.skip(r.i32()! * 8)!
		}
		else {
			return error('nbt_be: unknown tag ${tag_type}')
		}
	}
}

fn (mut r BeReader) read_palette_block() !BlockPaletteEntry {
	mut name := ''
	mut network_id := 0
	mut has_id := false
	for {
		entry_type := r.u8()!
		if entry_type == 0 {
			break
		}
		key := r.read_name()!
		if key == 'name' && entry_type == 8 {
			name = r.read_name()!
		} else if key == 'network_id' && entry_type == 3 {
			network_id = r.i32()!
			has_id = true
		} else {
			r.skip_payload(entry_type)!
		}
	}
	if name == '' || !has_id {
		return error('nbt_be: palette block missing name or network_id')
	}
	return BlockPaletteEntry{
		name:       name
		network_id: network_id
	}
}

pub fn parse_block_palette(data []u8) ![]BlockPaletteEntry {
	mut r := BeReader{
		data: data
	}
	root_type := r.u8()!
	if root_type != 10 {
		return error('nbt_be: root is not a compound')
	}
	r.read_name()!
	for {
		entry_type := r.u8()!
		if entry_type == 0 {
			break
		}
		key := r.read_name()!
		if key == 'blocks' && entry_type == 9 {
			element_type := r.u8()!
			if element_type != 10 {
				return error('nbt_be: blocks list elements are not compounds')
			}
			count := r.i32()!
			if count < 0 {
				return error('nbt_be: negative blocks count')
			}
			mut entries := []BlockPaletteEntry{cap: count}
			for _ in 0 .. count {
				entries << r.read_palette_block()!
			}
			return entries
		}
		r.skip_payload(entry_type)!
	}
	return error('nbt_be: blocks list not found')
}
