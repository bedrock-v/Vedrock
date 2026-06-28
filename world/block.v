module world

pub struct Block {
pub:
	name       string
	network_id int
}

pub fn new_block(name string) Block {
	return Block{
		name:       name
		network_id: block_state_hash(name)
	}
}

pub const air = new_block('minecraft:air')
pub const stone = new_block('minecraft:stone')
pub const grass_block = new_block('minecraft:grass_block')

fn block_state_hash(name string) int {
	if name == 'minecraft:unknown' {
		return -2
	}
	return int(fnv1a_32(le_nbt_block_state(name)))
}

fn le_nbt_block_state(name string) []u8 {
	mut b := []u8{}
	b << 0x0a
	put_u16_le(mut b, 0)
	put_string_tag(mut b, 'name', name)
	b << 0x0a
	put_u16_le(mut b, u16('states'.len))
	b << 'states'.bytes()
	b << 0x00
	b << 0x00
	return b
}

fn put_string_tag(mut b []u8, key string, value string) {
	b << 0x08
	put_u16_le(mut b, u16(key.len))
	b << key.bytes()
	put_u16_le(mut b, u16(value.len))
	b << value.bytes()
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
