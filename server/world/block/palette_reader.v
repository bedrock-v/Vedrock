module block

const tag_end = u8(0)
const tag_byte = u8(1)
const tag_short = u8(2)
const tag_int = u8(3)
const tag_long = u8(4)
const tag_float = u8(5)
const tag_double = u8(6)
const tag_byte_array = u8(7)
const tag_string = u8(8)
const tag_list = u8(9)
const tag_compound = u8(10)
const tag_int_array = u8(11)
const tag_long_array = u8(12)

// PaletteReader reads the big endian NBT the palette file is in.
//
// It has no limit on how deeply tags nest.
struct PaletteReader {
	data []u8
mut:
	offset int
}

fn (mut r PaletteReader) need(n int) ! {
	if n < 0 || r.offset + n > r.data.len {
		return error('the palette ends early at ${r.offset}')
	}
}

fn (mut r PaletteReader) u8() !u8 {
	r.need(1)!
	r.offset++
	return r.data[r.offset - 1]
}

fn (mut r PaletteReader) fixed(n int) !u64 {
	r.need(n)!
	mut v := u64(0)
	for i in 0 .. n {
		v = v << 8 | u64(r.data[r.offset + i])
	}
	r.offset += n
	return v
}

fn (mut r PaletteReader) length() !int {
	n := int(i32(r.fixed(4)!))
	r.need(n)!
	return n
}

fn (mut r PaletteReader) text() !string {
	n := int(r.fixed(2)!)
	r.need(n)!
	s := r.data[r.offset..r.offset + n].bytestr()
	r.offset += n
	return s
}

// state reads one entry of the blocks list. Only the name and the properties
// are kept; the network ID the file also carries is worked out from them.
fn (mut r PaletteReader) state() !State {
	mut name := ''
	mut properties := []Property{}
	for {
		id := r.u8()!
		if id == tag_end {
			break
		}
		key := r.text()!
		if id == tag_string && key == 'name' {
			name = r.text()!
		} else if id == tag_compound && key == 'states' {
			properties = r.properties()!
		} else {
			r.skip(id)!
		}
	}
	if name == '' {
		return error('a block has no name')
	}
	properties.sort(a.name < b.name)
	return State{
		name:       name
		properties: properties
	}
}

fn (mut r PaletteReader) properties() ![]Property {
	mut out := []Property{}
	for {
		id := r.u8()!
		if id == tag_end {
			return out
		}
		name := r.text()!
		value := match id {
			tag_byte { Value(r.u8()!) }
			tag_int { Value(i32(r.fixed(4)!)) }
			tag_string { Value(r.text()!) }
			else { return error('property ${name} is tag ${id}') }
		}
		out << Property{name, value}
	}
	return out
}

// skip passes over a value the registry doesn't keep.
fn (mut r PaletteReader) skip(id u8) ! {
	match id {
		tag_byte {
			r.need(1)!
			r.offset += 1
		}
		tag_short {
			r.need(2)!
			r.offset += 2
		}
		tag_int, tag_float {
			r.need(4)!
			r.offset += 4
		}
		tag_long, tag_double {
			r.need(8)!
			r.offset += 8
		}
		tag_byte_array {
			n := r.length()!
			r.offset += n
		}
		tag_string {
			r.text()!
		}
		tag_list {
			element := r.u8()!
			n := r.length()!
			for _ in 0 .. n {
				r.skip(element)!
			}
		}
		tag_compound {
			for {
				child := r.u8()!
				if child == tag_end {
					break
				}
				r.text()!
				r.skip(child)!
			}
		}
		tag_int_array {
			n := r.length()!
			r.need(n * 4)!
			r.offset += n * 4
		}
		tag_long_array {
			n := r.length()!
			r.need(n * 8)!
			r.offset += n * 8
		}
		else { return error('unknown tag ${id} at ${r.offset}') }
	}
}
