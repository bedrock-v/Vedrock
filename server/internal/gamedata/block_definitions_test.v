module gamedata

fn definitions() []BlockDefinition {
	return load_block_definitions('../data/block_definitions.nbt') or {
		load_block_definitions('data/block_definitions.nbt') or {
			panic('cannot find data dir: ${err}')
		}
	}
}

fn test_load_block_definitions_carries_names_and_properties() {
	defs := definitions()
	assert defs.len > 90
	mut by_name := map[string]BlockDefinition{}
	for def in defs {
		assert def.name.starts_with('minecraft:')
		by_name[def.name] = def
	}
	assert 'minecraft:white_wool_slab' in by_name
	assert 'minecraft:red_shrub' in by_name
	assert 'minecraft:shelf_mushroom' in by_name

	slab := by_name['minecraft:white_wool_slab'] or { panic('no white wool slab') }
	properties := tag_compound(slab.properties.tag) or { panic('properties are not a compound') }
	// The client reads its own render and menu state out of these, so an entry
	// that carries no components is one it cannot draw.
	assert child(properties, 'components') != none
	assert child(properties, 'vanilla_block_data') != none
}
