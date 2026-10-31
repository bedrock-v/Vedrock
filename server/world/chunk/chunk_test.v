module chunk

import server.world.block

fn stone() u32 {
	return block.vanilla().id(block.State{ name: 'minecraft:stone' }) or { panic('no stone') }
}

fn test_a_storage_keeps_every_value_as_it_grows() {
	mut s := new_storage(7)
	for i in 0 .. 4096 {
		s.set(i, u32(1000 + i))
	}
	assert s.bits == 16
	for i in 0 .. 4096 {
		assert s.at(i) == u32(1000 + i), 'block ${i} changed while the storage grew'
	}
}

fn test_a_sub_chunk_is_written_as_the_client_reads_it() {
	mut c := new(block.vanilla())
	c.set_block(0, min_y + 2, 1, 0, stone())
	data, count := c.encode()
	assert count == 1

	// Version 9, one layer, section -4.
	mut want := [u8(9), 1, 0xfc]
	// One bit per block, network form.
	want << u8(1 << 1 | 1)
	// 32 blocks a word. Block 18 (z 1 is 16, y 2 is 2) is stone, palette index 1.
	want << [u8(0), 0, 0x04, 0]
	for _ in 1 .. 4096 / 32 {
		want << [u8(0), 0, 0, 0]
	}
	// Two palette entries, then air and stone as zigzag varints of their hashes.
	want << u8(4)
	want << [u8(0xbf), 0xfb, 0xdd, 0xc0, 0x04]
	want << [u8(0xbd), 0xc7, 0xf7, 0xfc, 0x0f]
	assert data[..want.len] == want
}

fn test_the_bottom_and_top_blocks_are_in_the_first_and_last_sections() {
	mut bottom := new(block.vanilla())
	bottom.set_block(15, min_y, 15, 0, stone())
	_, count := bottom.encode()
	assert count == 1, 'the bottom block is not in the first section'

	mut top := new(block.vanilla())
	top.set_block(15, max_y, 15, 0, stone())
	data, top_count := top.encode()
	assert top_count == overworld_sections, 'the top block is not in the last section'
	assert top.block(15, max_y, 15, 0) == stone()
	last := (overworld_sections - 1) * 3
	assert data[last..last + 3] == [u8(9), 1, u8(max_y >> 4)]
}

fn test_a_compacted_chunk_drops_blocks_that_are_gone() {
	reg := block.vanilla()
	mut c := new(reg)
	for i in 0 .. 300 {
		c.set_block(i % 16, min_y + 16 + i / 256, i / 16 % 16, 0, u32(i))
	}
	// Set before the stone. Dropping it moves the stone's palette index.
	c.set_block(5, min_y, 6, 0, u32(7))
	c.set_block(3, min_y, 4, 0, stone())
	for i in 0 .. 300 {
		c.set_block(i % 16, min_y + 16 + i / 256, i / 16 % 16, 0, reg.air)
	}
	c.set_block(5, min_y, 6, 0, reg.air)
	c.compact()
	_, count := c.encode()
	assert count == 1, 'a section cleared back to air still went out'
	assert c.block(3, min_y, 4, 0) == stone(), 'compacting lost a block that is still there'
	assert c.sections[0].layers[0].palette.len == 2, 'a block that is gone kept its palette entry'
	assert c.sections[0].layers[0].bits == 1
}
