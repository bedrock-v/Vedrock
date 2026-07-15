module gamedata

fn be_i16(mut b []u8, v int) {
	b << u8((v >> 8) & 0xff)
	b << u8(v & 0xff)
}

fn be_i32(mut b []u8, v int) {
	u := u32(v)
	b << u8((u >> 24) & 0xff)
	b << u8((u >> 16) & 0xff)
	b << u8((u >> 8) & 0xff)
	b << u8(u & 0xff)
}

fn be_string_tag(mut b []u8, key string, value string) {
	b << 0x08
	be_i16(mut b, key.len)
	b << key.bytes()
	be_i16(mut b, value.len)
	b << value.bytes()
}

fn be_int_tag(mut b []u8, key string, value int) {
	b << 0x03
	be_i16(mut b, key.len)
	b << key.bytes()
	be_i32(mut b, value)
}

fn be_palette_entry(mut b []u8, name string, network_id int) {
	be_int_tag(mut b, 'network_id', network_id)
	// A long field the parser must skip like the real palette's name_hash.
	b << 0x04
	be_i16(mut b, 9)
	b << 'name_hash'.bytes()
	for _ in 0 .. 8 {
		b << u8(0xab)
	}
	be_string_tag(mut b, 'name', name)
	be_int_tag(mut b, 'version', 18163713)
	// Empty states compound as in the real palette.
	b << 0x0a
	be_i16(mut b, 6)
	b << 'states'.bytes()
	b << 0x00
	b << 0x00
}

fn build_palette(entries []BlockPaletteEntry) []u8 {
	mut b := []u8{}
	b << 0x0a
	be_i16(mut b, 0)
	b << 0x09
	be_i16(mut b, 6)
	b << 'blocks'.bytes()
	b << 0x0a
	be_i32(mut b, entries.len)
	for e in entries {
		be_palette_entry(mut b, e.name, e.network_id)
	}
	b << 0x00
	return b
}

fn test_parse_block_palette_preserves_order_and_ids() {
	data := build_palette([
		BlockPaletteEntry{'minecraft:oak_stairs', 111},
		BlockPaletteEntry{'minecraft:oak_stairs', 222},
		BlockPaletteEntry{'minecraft:beacon', -333},
	])
	entries := parse_block_palette(data) or { panic(err) }
	assert entries.len == 3
	assert entries[0].name == 'minecraft:oak_stairs'
	assert entries[0].network_id == 111
	assert entries[1].network_id == 222
	assert entries[2].name == 'minecraft:beacon'
	assert entries[2].network_id == -333
}

fn test_parse_block_palette_rejects_non_compound_root() {
	if _ := parse_block_palette([u8(0x09), 0x00, 0x00]) {
		assert false, 'list root should be rejected'
	}
}

fn test_parse_block_palette_rejects_truncated_data() {
	data := build_palette([BlockPaletteEntry{'minecraft:stone', 1}])
	if _ := parse_block_palette(data[..data.len / 2]) {
		assert false, 'truncated palette should error, not panic'
	}
}
