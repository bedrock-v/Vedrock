module item

fn test_combat_durability_items_registered() {
	r := new_registry()
	shield := r.get('minecraft:shield') or { panic('missing shield') }
	assert shield.durability() == 336
	assert shield.max_stack_size() == 1

	bow := r.get('minecraft:bow') or { panic('missing bow') }
	assert bow.durability() == 384

	crossbow := r.get('minecraft:crossbow') or { panic('missing crossbow') }
	assert crossbow.durability() == 465

	trident := r.get('minecraft:trident') or { panic('missing trident') }
	assert trident.durability() == 250
	assert trident.attack_damage() == 9
}

fn test_progression_block_items_place_their_block() {
	r := new_registry()
	for id in ['minecraft:enchanting_table', 'minecraft:bookshelf', 'minecraft:anvil',
		'minecraft:chipped_anvil', 'minecraft:damaged_anvil', 'minecraft:grindstone',
		'minecraft:brewing_stand', 'minecraft:cauldron'] {
		it := r.get(id) or { panic('missing ${id}') }
		assert it.block_runtime_id() != 0
	}
}

fn test_deprecated_anvil_has_no_item() {
	r := new_registry()
	assert r.get('minecraft:deprecated_anvil') == none
}

fn test_ammo_and_misc_combat_items_registered() {
	r := new_registry()
	arrow := r.get('minecraft:arrow') or { panic('missing arrow') }
	assert arrow.max_stack_size() == 64

	totem := r.get('minecraft:totem_of_undying') or { panic('missing totem_of_undying') }
	assert totem.max_stack_size() == 1

	xp_bottle := r.get('minecraft:experience_bottle') or { panic('missing experience_bottle') }
	assert xp_bottle.max_stack_size() == 64

	glass_bottle := r.get('minecraft:glass_bottle') or { panic('missing glass_bottle') }
	assert glass_bottle.max_stack_size() == 64
}

fn test_splash_and_lingering_potions_registered_unstackable() {
	r := new_registry()
	splash := r.get('minecraft:splash_potion') or { panic('missing splash_potion') }
	assert splash.max_stack_size() == 1
	lingering := r.get('minecraft:lingering_potion') or { panic('missing lingering_potion') }
	assert lingering.max_stack_size() == 1
}
