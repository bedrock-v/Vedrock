module world

fn test_dimension_max_y() {
	assert overworld.max_y() == dimension_max_y
	assert nether.max_y() == 127
	assert the_end.max_y() == 255
}

fn test_dimension_by_id() {
	assert dimension_by_id(0)?.id == overworld.id
	assert dimension_by_id(1)?.id == nether.id
	assert dimension_by_id(2)?.id == the_end.id
	if _ := dimension_by_id(3) {
		assert false, 'dimension id 3 should not resolve'
	}
}

fn test_dimension_by_name() {
	assert dimension_by_name('Nether')?.id == nether.id
	assert dimension_by_name('the_end')?.id == the_end.id
	assert dimension_by_name('world')?.id == overworld.id
	if _ := dimension_by_name('moon') {
		assert false, 'unknown dimension name should not resolve'
	}
}

fn test_new_chunk_dim_sizes_sections_per_dimension() {
	assert new_chunk_dim(nether).section_count() == 0
	mut c := new_chunk_dim(nether)
	c.set_block(0, 100, 0, stone)
	assert c.block_id(0, 100, 0) == stone.network_id
	c.set_block(0, 200, 0, stone)
	assert c.block_id(0, 200, 0) == air.network_id
}
