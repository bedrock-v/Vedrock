module world

pub const state_kind_byte = 0
pub const state_kind_string = 1
pub const state_kind_int = 2

pub struct BlockState {
pub:
	key        string
	kind       int
	byte_value u8
	string_val string
	int_value  int
}

pub struct Block {
pub:
	name       string
	network_id int
}

pub fn new_block(name string) Block {
	return new_block_with_states(name, [])
}

pub fn block_from_id(network_id int) Block {
	return Block{
		name:       ''
		network_id: network_id
	}
}

pub fn new_block_with_states(name string, states []BlockState) Block {
	return Block{
		name:       name
		network_id: block_state_hash(name, states)
	}
}

// Network IDs must match data/block_palette.nbt (FNV1a-32 of the canonical
// little-endian block state NBT). Values verified against the palette dump:
// air=-604749536 stone=-2144268767 grass_block=-567203660
// bedrock(infiniburn_bit=0)=-173245189 dirt=-2108756090
pub const air = new_block('minecraft:air')
pub const stone = new_block('minecraft:stone')
pub const grass_block = new_block('minecraft:grass_block')
pub const bedrock = new_block_with_states('minecraft:bedrock', [
	BlockState{
		key:        'infiniburn_bit'
		kind:       state_kind_byte
		byte_value: 0
	},
])
pub const dirt = new_block('minecraft:dirt')

fn block_state_hash(name string, states []BlockState) int {
	if name == 'minecraft:unknown' {
		return -2
	}
	return int(fnv1a_32(le_nbt_block_state(name, states)))
}

fn sorted_states(states []BlockState) []BlockState {
	mut out := states.clone()
	for i in 0 .. out.len {
		for j in i + 1 .. out.len {
			if out[j].key < out[i].key {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out
}

fn le_nbt_block_state(name string, states []BlockState) []u8 {
	mut b := []u8{}
	b << 0x0a
	put_u16_le(mut b, 0)
	put_string_tag(mut b, 'name', name)
	b << 0x0a
	put_name(mut b, 'states')
	for state in sorted_states(states) {
		match state.kind {
			state_kind_string {
				put_string_tag(mut b, state.key, state.string_val)
			}
			state_kind_int {
				b << 0x03
				put_name(mut b, state.key)
				put_i32_le(mut b, state.int_value)
			}
			else {
				b << 0x01
				put_name(mut b, state.key)
				b << state.byte_value
			}
		}
	}
	b << 0x00
	b << 0x00
	return b
}

fn put_name(mut b []u8, name string) {
	put_u16_le(mut b, u16(name.len))
	b << name.bytes()
}

fn put_string_tag(mut b []u8, key string, value string) {
	b << 0x08
	put_name(mut b, key)
	put_u16_le(mut b, u16(value.len))
	b << value.bytes()
}

fn put_i32_le(mut b []u8, value int) {
	u := u32(value)
	b << u8(u & 0xff)
	b << u8((u >> 8) & 0xff)
	b << u8((u >> 16) & 0xff)
	b << u8((u >> 24) & 0xff)
}

fn put_u16_le(mut b []u8, value u16) {
	b << u8(value & 0xff)
	b << u8((value >> 8) & 0xff)
}

fn fnv1a_32(data []u8) u32 {
	mut hash := u32(0x811c9dc5)
	for byte_value in data {
		hash ^= u32(byte_value)
		hash *= u32(0x01000193)
	}
	return hash
}
