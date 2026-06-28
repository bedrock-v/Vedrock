module gamedata

struct LeReader {
	data []u8
mut:
	pos int
}

fn (mut r LeReader) u8() !u8 {
	if r.pos >= r.data.len {
		return error('nbt_le: out of bounds')
	}
	value := r.data[r.pos]
	r.pos++
	return value
}

fn (mut r LeReader) skip(n int) ! {
	if r.pos + n > r.data.len {
		return error('nbt_le: skip out of bounds')
	}
	r.pos += n
}

fn (mut r LeReader) i16() !int {
	low := int(r.u8()!)
	high := int(r.u8()!)
	return low | (high << 8)
}

fn (mut r LeReader) i32() !int {
	mut value := 0
	for i in 0 .. 4 {
		value |= int(r.u8()!) << (8 * i)
	}
	return value
}

fn (mut r LeReader) read_name() !string {
	length := r.i16()!
	if r.pos + length > r.data.len {
		return error('nbt_le: name out of bounds')
	}
	name := r.data[r.pos..r.pos + length].bytestr()
	r.pos += length
	return name
}

fn (mut r LeReader) skip_payload(tag_type u8) ! {
	match tag_type {
		1 { r.skip(1)! }
		2 { r.skip(2)! }
		3 { r.skip(4)! }
		4 { r.skip(8)! }
		5 { r.skip(4)! }
		6 { r.skip(8)! }
		7 { r.skip(r.i32()!)! }
		8 { r.skip(r.i16()!)! }
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
		11 { r.skip(r.i32()! * 4)! }
		12 { r.skip(r.i32()! * 8)! }
		else { return error('nbt_le: unknown tag ${tag_type}') }
	}
}

pub fn block_network_id_from_nbt(data []u8) !int {
	mut r := LeReader{
		data: data
	}
	root_type := r.u8()!
	if root_type != 10 {
		return error('nbt_le: root is not a compound')
	}
	r.read_name()!
	for {
		entry_type := r.u8()!
		if entry_type == 0 {
			break
		}
		name := r.read_name()!
		if name == 'network_id' && entry_type == 3 {
			return r.i32()!
		}
		r.skip_payload(entry_type)!
	}
	return error('nbt_le: network_id not found')
}
