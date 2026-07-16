module block

fn test_anvil_stages_registered_with_all_directions() {
	r := new_registry()
	for name in ['anvil', 'chipped_anvil', 'damaged_anvil'] {
		south := anvil_block(name, 'south')
		east := anvil_block(name, 'east')
		assert south.runtime_id() != east.runtime_id()
		b := r.get(south.runtime_id()) or { panic('missing ${name} direction=south') }
		assert b.hardness() == 5.0
	}
}

fn test_deprecated_anvil_registered_for_chunk_load() {
	r := new_registry()
	south := anvil_block('deprecated_anvil', 'south')
	b := r.get(south.runtime_id()) or { panic('missing deprecated_anvil direction=south') }
	assert b.hardness() == 5.0
}

fn test_grindstone_attachment_and_direction_variants_registered() {
	r := new_registry()
	standing := grindstone_block('standing', 0)
	hanging := grindstone_block('hanging', 3)
	assert standing.runtime_id() != hanging.runtime_id()
	b := r.get(standing.runtime_id()) or { panic('missing grindstone standing/0') }
	assert b.hardness() == 2.0
}

fn test_brewing_stand_slot_bit_combos_registered() {
	r := new_registry()
	empty := brewing_stand_block(0, 0, 0)
	full := brewing_stand_block(1, 1, 1)
	assert empty.runtime_id() != full.runtime_id()
	b := r.get(empty.runtime_id()) or { panic('missing empty brewing_stand') }
	assert b.hardness() == 0.5
}

fn test_cauldron_liquid_and_fill_level_variants_registered() {
	r := new_registry()
	empty_water := cauldron_block('water', 0)
	full_lava := cauldron_block('lava', 6)
	assert empty_water.runtime_id() != full_lava.runtime_id()
	b := r.get(empty_water.runtime_id()) or { panic('missing empty water cauldron') }
	assert b.hardness() == 2.0
}

fn test_enchanting_table_and_bookshelf_registered() {
	r := new_registry()
	table := r.get_by_name('minecraft:enchanting_table') or { panic('missing enchanting_table') }
	assert table.hardness() == 5.0
	shelf := r.get_by_name('minecraft:bookshelf') or { panic('missing bookshelf') }
	assert shelf.hardness() == 1.5
}
