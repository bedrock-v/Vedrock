module gamedata

import bedrock_v.nbt

// parse_block_palette in nbt_be.v skips everything it does not need. Loading
// Mojang's registry files needs the whole document instead, so this reader
// builds the same tag tree the network codec uses. The format itself is the
// big endian on-disk one: fixed width numbers and length prefixed strings,
// against the varint little endian form used on the wire.
struct BigEndianTagReader {
	data []u8
mut:
	offset int
}

fn (mut r BigEndianTagReader) need(count int) ! {
	if count < 0 || r.offset + count > r.data.len {
		return error('nbt_be_tree: read past end of data')
	}
}

fn (mut r BigEndianTagReader) u8() !u8 {
	r.need(1)!
	value := r.data[r.offset]
	r.offset++
	return value
}

fn (mut r BigEndianTagReader) be_u16() !u16 {
	r.need(2)!
	value := (u16(r.data[r.offset]) << 8) | u16(r.data[r.offset + 1])
	r.offset += 2
	return value
}

fn (mut r BigEndianTagReader) be_u32() !u32 {
	r.need(4)!
	mut value := u32(0)
	for i in 0 .. 4 {
		value = (value << 8) | u32(r.data[r.offset + i])
	}
	r.offset += 4
	return value
}

fn (mut r BigEndianTagReader) be_u64() !u64 {
	r.need(8)!
	mut value := u64(0)
	for i in 0 .. 8 {
		value = (value << 8) | u64(r.data[r.offset + i])
	}
	r.offset += 8
	return value
}

fn (mut r BigEndianTagReader) read_string() !string {
	length := int(r.be_u16()!)
	r.need(length)!
	value := r.data[r.offset..r.offset + length].bytestr()
	r.offset += length
	return value
}

fn (mut r BigEndianTagReader) read_payload(tag_id u8) !nbt.Tag {
	match tag_id {
		nbt.tag_byte {
			return nbt.Tag(i8(r.u8()!))
		}
		nbt.tag_short {
			return nbt.Tag(i16(r.be_u16()!))
		}
		nbt.tag_int {
			return nbt.Tag(i32(r.be_u32()!))
		}
		nbt.tag_long {
			return nbt.Tag(i64(r.be_u64()!))
		}
		nbt.tag_float {
			return nbt.Tag(bits_to_f32(r.be_u32()!))
		}
		nbt.tag_double {
			return nbt.Tag(bits_to_f64(r.be_u64()!))
		}
		nbt.tag_byte_array {
			count := int(r.be_u32()!)
			r.need(count)!
			values := r.data[r.offset..r.offset + count].clone()
			r.offset += count
			return nbt.Tag(nbt.ByteArray{
				values: values
			})
		}
		nbt.tag_string {
			return nbt.Tag(r.read_string()!)
		}
		nbt.tag_list {
			element_type := r.u8()!
			count := int(r.be_u32()!)
			mut values := []nbt.Tag{cap: count}
			for _ in 0 .. count {
				values << r.read_payload(element_type)!
			}
			return nbt.Tag(nbt.List{
				element_type: element_type
				values:       values
			})
		}
		nbt.tag_compound {
			mut compound := nbt.new_compound()
			for {
				child_id := r.u8()!
				if child_id == nbt.tag_end {
					break
				}
				name := r.read_string()!
				compound.set(name, r.read_payload(child_id)!)
			}
			return nbt.Tag(compound)
		}
		nbt.tag_int_array {
			count := int(r.be_u32()!)
			mut values := []i32{cap: count}
			for _ in 0 .. count {
				values << i32(r.be_u32()!)
			}
			return nbt.Tag(nbt.IntArray{
				values: values
			})
		}
		nbt.tag_long_array {
			count := int(r.be_u32()!)
			mut values := []i64{cap: count}
			for _ in 0 .. count {
				values << i64(r.be_u64()!)
			}
			return nbt.Tag(nbt.LongArray{
				values: values
			})
		}
		else {
			return error('nbt_be_tree: unknown tag id ${tag_id}')
		}
	}
}

fn bits_to_f32(bits u32) f32 {
	return unsafe { *(&f32(&bits)) }
}

fn bits_to_f64(bits u64) f64 {
	return unsafe { *(&f64(&bits)) }
}

// parse_be_nbt decodes a big endian NBT document into the same tag tree the
// network codec uses, so callers can walk both forms with one set of helpers.
pub fn parse_be_nbt(data []u8) !nbt.RootTag {
	mut r := BigEndianTagReader{
		data: data
	}
	tag_id := r.u8()!
	if tag_id != nbt.tag_compound {
		return error('nbt_be_tree: root tag must be a compound, got ${tag_id}')
	}
	name := r.read_string()!
	return nbt.RootTag{
		name: name
		tag:  r.read_payload(tag_id)!
	}
}
