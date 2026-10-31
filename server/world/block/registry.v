module block

import compress.gzip

// palette_data is every vanilla block state.
const palette_data = $embed_file('block_palette.nbt').to_bytes()

// vanilla_registry is read once and only read after.
// The data is part of the build.
const vanilla_registry = load(palette_data) or { panic('block: the embedded palette: ${err}') }

// Value is the value of a block state's property.
pub type Value = i32 | string | u8

// Property is one named property of a block state such as a log's axis.
pub struct Property {
pub:
	name  string
	value Value
}

// State is one form a block can take: its name and the value of each of its
// properties, sorted by property name.
pub struct State {
pub:
	name       string
	properties []Property
}

// Registry holds every block state the server knows. A state's ID is its
// index here.
@[heap]
pub struct Registry {
pub:
	// air is the ID of air.
	air u32
mut:
	states  []State
	hashes  []u32
	by_hash map[u32]u32
}

// vanilla is the registry of every vanilla block state.
pub fn vanilla() &Registry {
	return vanilla_registry
}

// len is how many states there are. IDs run from 0 to len - 1.
pub fn (r &Registry) len() int {
	return r.states.len
}

// state is the state with an ID.
pub fn (r &Registry) state(id u32) State {
	return r.states[id]
}

// hash is the network ID of a state.
pub fn (r &Registry) hash(id u32) u32 {
	return r.hashes[id]
}

// by_hash is the state a network ID stands for. A client can send any number,
// and one that names no state is none.
pub fn (r &Registry) by_hash(hash u32) ?u32 {
	return r.by_hash[hash] or { return none }
}

// id is the ID of a state, or none for a state the registry doesn't have.
pub fn (r &Registry) id(s State) ?u32 {
	// The hash is over sorted properties and a caller can name them in any order.
	mut sorted := State{
		...s
		properties: s.properties.clone()
	}
	sorted.properties.sort(a.name < b.name)
	mut scratch := []u8{}
	id := r.by_hash(state_hash(sorted, mut scratch) or { return none })?
	// A state the registry doesn't have can share a hash with one it does.
	if !same_state(r.states[id], sorted) {
		return none
	}
	return id
}

fn load(gzipped []u8) !&Registry {
	mut r := PaletteReader{
		data: gzip.decompress(gzipped)!
	}
	if r.u8()! != tag_compound {
		return error('the palette is not a compound')
	}
	r.skip(tag_string)!
	mut reg := &Registry{
		by_hash: map[u32]u32{}
	}
	mut air := ?u32(none)
	mut scratch := []u8{cap: 256}
	for {
		id := r.u8()!
		if id == tag_end {
			break
		}
		key := r.text()!
		if id != tag_list || key != 'blocks' {
			r.skip(id)!
			continue
		}
		if r.u8()! != tag_compound {
			return error('blocks is not a list of compounds')
		}
		count := r.length()!
		reg.states = []State{cap: count}
		reg.hashes = []u32{cap: count}
		for _ in 0 .. count {
			s := r.state()!
			hash := state_hash(s, mut scratch)!
			if other := reg.by_hash[hash] {
				return error('${s.name} and ${reg.states[other].name} have the same hash ${hash}')
			}
			if s.name == 'minecraft:air' {
				air = u32(reg.states.len)
			}
			reg.by_hash[hash] = u32(reg.states.len)
			reg.states << s
			reg.hashes << hash
		}
	}
	return &Registry{
		...reg
		air: air or { return error('there is no air') }
	}
}

fn state_hash(s State, mut scratch []u8) !u32 {
	scratch.clear()
	scratch << tag_compound
	put_str(mut scratch, '')!
	scratch << tag_string
	put_str(mut scratch, 'name')!
	put_str(mut scratch, s.name)!
	scratch << tag_compound
	put_str(mut scratch, 'states')!
	for p in s.properties {
		match p.value {
			u8 {
				scratch << tag_byte
				put_str(mut scratch, p.name)!
				scratch << p.value
			}
			i32 {
				scratch << tag_int
				put_str(mut scratch, p.name)!
				v := u32(p.value)
				scratch << [u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)]
			}
			string {
				scratch << tag_string
				put_str(mut scratch, p.name)!
				put_str(mut scratch, p.value)!
			}
		}
	}
	scratch << tag_end
	scratch << tag_end
	mut h := u32(0x811c9dc5)
	for b in scratch {
		h ^= u32(b)
		h *= 0x01000193
	}
	return h
}

// put_str writes a little endian NBT string: a u16 length, then the bytes.
fn put_str(mut out []u8, s string) ! {
	if s.len > 0xffff {
		return error('${s.len} bytes is too long for an NBT string')
	}
	out << [u8(s.len), u8(s.len >> 8)]
	out << s.bytes()
}

fn same_state(a State, b State) bool {
	if a.name != b.name || a.properties.len != b.properties.len {
		return false
	}
	for i, p in a.properties {
		q := b.properties[i]
		if p.name != q.name || !same_value(p.value, q.value) {
			return false
		}
	}
	return true
}

fn same_value(a Value, b Value) bool {
	return match a {
		u8 { b is u8 && a == b as u8 }
		i32 { b is i32 && a == b as i32 }
		string { b is string && a == b as string }
	}
}
