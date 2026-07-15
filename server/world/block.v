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

pub const coal_ore = new_block('minecraft:coal_ore')
pub const iron_ore = new_block('minecraft:iron_ore')
pub const gold_ore = new_block('minecraft:gold_ore')
pub const diamond_ore = new_block('minecraft:diamond_ore')
pub const emerald_ore = new_block('minecraft:emerald_ore')
pub const copper_ore = new_block('minecraft:copper_ore')
pub const redstone_ore = new_block('minecraft:redstone_ore')
pub const lapis_ore = new_block('minecraft:lapis_ore')

pub const coal_block = new_block('minecraft:coal_block')
pub const iron_block = new_block('minecraft:iron_block')
pub const gold_block = new_block('minecraft:gold_block')
pub const diamond_block = new_block('minecraft:diamond_block')
pub const emerald_block = new_block('minecraft:emerald_block')
pub const copper_block = new_block('minecraft:copper_block')
pub const redstone_block = new_block('minecraft:redstone_block')
pub const lapis_block = new_block('minecraft:lapis_block')

pub const cobblestone = new_block('minecraft:cobblestone')
pub const sand = new_block('minecraft:sand')
pub const red_sand = new_block('minecraft:red_sand')
pub const gravel = new_block('minecraft:gravel')
pub const sandstone = new_block('minecraft:sandstone')
pub const andesite = new_block('minecraft:andesite')
pub const polished_andesite = new_block('minecraft:polished_andesite')
pub const diorite = new_block('minecraft:diorite')
pub const polished_diorite = new_block('minecraft:polished_diorite')
pub const granite = new_block('minecraft:granite')
pub const polished_granite = new_block('minecraft:polished_granite')
pub const netherrack = new_block('minecraft:netherrack')
pub const end_stone = new_block('minecraft:end_stone')
pub const obsidian = new_block('minecraft:obsidian')
pub const ice = new_block('minecraft:ice')
pub const snow = new_block('minecraft:snow')
pub const clay = new_block('minecraft:clay')
pub const mossy_cobblestone = new_block('minecraft:mossy_cobblestone')
pub const packed_ice = new_block('minecraft:packed_ice')
pub const blue_ice = new_block('minecraft:blue_ice')
pub const cobbled_deepslate = new_block('minecraft:cobbled_deepslate')
pub const tuff = new_block('minecraft:tuff')
pub const calcite = new_block('minecraft:calcite')
pub const smooth_basalt = new_block('minecraft:smooth_basalt')
pub const dripstone_block = new_block('minecraft:dripstone_block')

pub const soul_sand = new_block('minecraft:soul_sand')
pub const soul_soil = new_block('minecraft:soul_soil')
pub const glowstone = new_block('minecraft:glowstone')
pub const magma_block = new_block('minecraft:magma')
pub const purpur_block = new_block('minecraft:purpur_block')
pub const end_bricks = new_block('minecraft:end_bricks')

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
