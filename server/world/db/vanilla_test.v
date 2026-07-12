module db

import os

const air_id = -604749536
const stone_id = -2144268767
const grass_id = -567203660
const bedrock_id = -173245189

fn le_u16(mut b []u8, v u16) {
	b << u8(v & 0xff)
	b << u8(v >> 8)
}

fn le_i32(mut b []u8, v int) {
	u := u32(v)
	b << u8(u & 0xff)
	b << u8((u >> 8) & 0xff)
	b << u8((u >> 16) & 0xff)
	b << u8((u >> 24) & 0xff)
}

fn nbt_string(mut b []u8, key string, value string) {
	b << 0x08
	le_u16(mut b, u16(key.len))
	b << key.bytes()
	le_u16(mut b, u16(value.len))
	b << value.bytes()
}

fn palette_entry(name string, byte_states map[string]u8) []u8 {
	mut b := []u8{}
	b << 0x0a
	le_u16(mut b, 0)
	nbt_string(mut b, 'name', name)
	b << 0x0a
	le_u16(mut b, 6)
	b << 'states'.bytes()
	for key, value in byte_states {
		b << 0x01
		le_u16(mut b, u16(key.len))
		b << key.bytes()
		b << value
	}
	b << 0x00
	b << 0x03
	le_u16(mut b, 7)
	b << 'version'.bytes()
	le_i32(mut b, 18163713)
	b << 0x00
	return b
}

fn build_subchunk(indices []int, bits int, palette [][]u8) []u8 {
	mut b := []u8{}
	b << 9
	b << 1
	b << u8(i8(-4))
	b << u8(bits << 1)
	per_word := 32 / bits
	word_count := (4096 + per_word - 1) / per_word
	for w in 0 .. word_count {
		mut word := u32(0)
		for i in 0 .. per_word {
			pos := w * per_word + i
			if pos < 4096 {
				word |= u32(indices[pos]) << (i * bits)
			}
		}
		le_i32(mut b, int(word))
	}
	le_i32(mut b, palette.len)
	for entry in palette {
		b << entry
	}
	return b
}

fn test_decode_subchunk_palette_hashes() {
	mut indices := []int{len: 4096}
	indices[0] = 1
	indices[1] = 2
	indices[4095] = 3
	data := build_subchunk(indices, 2, [
		palette_entry('minecraft:air', {}),
		palette_entry('minecraft:stone', {}),
		palette_entry('minecraft:grass_block', {}),
		palette_entry('minecraft:bedrock', {
			'infiniburn_bit': u8(0)
		}),
	])
	ids := decode_subchunk(data) or { panic(err) }
	assert ids.len == 4096
	assert ids[0] == stone_id
	assert ids[1] == grass_id
	assert ids[2] == air_id
	assert ids[4095] == bedrock_id
}

fn test_decode_subchunk_single_palette() {
	mut b := []u8{}
	b << 8
	b << 1
	b << 0x00
	b << palette_entry('minecraft:stone', {})
	ids := decode_subchunk(b) or { panic(err) }
	assert ids[0] == stone_id
	assert ids[4095] == stone_id
}

fn test_load_chunk_roundtrip() {
	dir := os.join_path(os.temp_dir(), 'vedrock_vanilla_test')
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
	mut store := open_world(dir) or { panic(err) }
	mut indices := []int{len: 4096}
	indices[0] = 1
	data := build_subchunk(indices, 1, [
		palette_entry('minecraft:air', {}),
		palette_entry('minecraft:grass_block', {}),
	])
	store.db.put(subchunk_key(3, -2, 0), data)
	chunk := store.load_chunk(3, -2) or { panic('chunk not found') }
	assert chunk.block_id(0, 0, 0) == grass_id
	assert chunk.block_id(1, 0, 0) == air_id
	assert store.load_chunk(9, 9) == none
	store.close()
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
}
