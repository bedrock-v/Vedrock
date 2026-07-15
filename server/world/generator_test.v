module world

fn test_flat_generator_matches_vanilla_superflat_preset() {
	g := FlatGenerator{}
	chunk := g.generate(0, 0)
	assert chunk.block_id(0, overworld.min_y, 0) == bedrock.network_id
	assert chunk.block_id(0, overworld.min_y + 1, 0) == dirt.network_id
	assert chunk.block_id(0, overworld.min_y + 2, 0) == dirt.network_id
	assert chunk.block_id(0, overworld.min_y + 3, 0) == grass_block.network_id
	assert g.block_at(0, overworld.min_y, 0) == bedrock.network_id
	assert g.block_at(0, overworld.min_y + 1, 0) == dirt.network_id
}

fn test_generator_registry_has_builtins() {
	r := new_generator_registry()
	names := r.names()
	assert 'void' in names
	assert 'flat' in names
	assert 'normal' in names
	assert 'nether' in names
	assert 'end' in names
}

fn test_generator_registry_create_unknown_returns_none() {
	r := new_generator_registry()
	if _ := r.create('moon', overworld) {
		assert false, 'unregistered generator name should not resolve'
	}
}

fn test_generator_registry_register_overrides_builtin() {
	mut r := new_generator_registry()
	r.register('flat', fn (dim Dimension) Generator {
		return VoidGenerator{
			dim: dim
		}
	})
	gen := r.create('flat', overworld) or { panic('expected flat to resolve') }
	assert !gen.uses_blocks()
}

fn test_generator_registry_builds_dimension_sized_chunks() {
	r := new_generator_registry()
	flat := r.create('flat', nether) or { panic('expected flat to resolve') }
	chunk := flat.generate(0, 0)

	assert chunk.subchunk_count == nether.subchunk_count
	assert chunk.block_id(0, nether.min_y, 0) == bedrock.network_id
	assert chunk.block_id(0, nether.min_y + 3, 0) == grass_block.network_id
	assert flat.spawn_y() == nether.min_y + 4
}

fn test_nether_generator_has_bedrock_floor_and_ceiling() {
	g := NetherGenerator{}
	chunk := g.generate(0, 0)
	assert chunk.block_id(0, nether.min_y, 0) == bedrock.network_id
	assert chunk.block_id(0, nether.min_y + 1, 0) == netherrack.network_id
	assert chunk.block_id(0, nether.min_y + 3, 0) == netherrack.network_id
	assert chunk.block_id(0, nether.max_y(), 0) == bedrock.network_id
	assert chunk.block_id(0, nether.min_y + 4, 0) == air.network_id
	assert g.spawn_y() == nether.min_y + 4
	assert g.block_at(0, nether.max_y(), 0) == bedrock.network_id
	assert g.block_at(0, nether.min_y, 0) == bedrock.network_id
}

fn test_end_generator_has_flat_floor_and_spawn_platform() {
	g := EndGenerator{}
	spawn_chunk := g.generate(0, 0)
	floor_top_y := the_end.min_y + 3
	platform_y := the_end.min_y + 4
	assert spawn_chunk.block_id(0, the_end.min_y, 0) == bedrock.network_id
	assert spawn_chunk.block_id(2, floor_top_y, 2) == end_stone.network_id
	assert spawn_chunk.block_id(10, floor_top_y, 10) == end_stone.network_id
	assert spawn_chunk.block_id(2, platform_y, 2) == obsidian.network_id
	assert spawn_chunk.block_id(10, platform_y, 10) == air.network_id
	other_chunk := g.generate(3, 3)
	assert other_chunk.block_id(2, platform_y, 2) == air.network_id
	assert other_chunk.block_id(2, floor_top_y, 2) == end_stone.network_id
	assert g.block_at(2, platform_y, 2) == obsidian.network_id
	assert g.block_at(10, platform_y, 10) == air.network_id
	assert g.spawn_y() == platform_y
}

fn test_generator_registry_void_and_normal_respect_dimension() {
	r := new_generator_registry()
	void := r.create('void', the_end) or { panic('expected void to resolve') }
	assert void.generate(0, 0).subchunk_count == the_end.subchunk_count

	normal := r.create('normal', nether) or { panic('expected normal to resolve') }
	chunk := normal.generate(0, 0)
	assert chunk.subchunk_count == nether.subchunk_count
	assert normal.spawn_y() >= nether.min_y && normal.spawn_y() <= nether.max_y()
}
