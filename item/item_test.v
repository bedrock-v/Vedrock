module item

fn test_default_registry_has_builtins() {
	r := new_registry()
	assert r.len() == 13
}

fn test_registered_blocks_carry_runtime_id() {
	r := new_registry()
	it := r.get('minecraft:stone') or { panic('missing stone') }
	assert it.max_stack_size() == 64
	if it is BlockItem {
		assert it.placed_block_runtime_id() != 0
	} else {
		assert false, 'stone is not a BlockItem'
	}
}

fn test_registered_foods_restore() {
	r := new_registry()
	it := r.get('minecraft:cooked_beef') or { panic('missing cooked_beef') }
	if it is FoodItem {
		assert it.restores() == 8
	} else {
		assert false, 'cooked_beef is not a FoodItem'
	}
}

fn test_sword_never_stacks() {
	r := new_registry()
	it := r.get('minecraft:diamond_sword') or { panic('missing sword') }
	assert it.max_stack_size() == 1
	if it is SwordItem {
		assert it.damage() == 7
	} else {
		assert false, 'diamond_sword is not a SwordItem'
	}
}

fn test_food_stacks_and_restores() {
	r := new_registry()
	it := r.get('minecraft:apple') or { panic('missing apple') }
	assert it.max_stack_size() == 64
	if it is FoodItem {
		assert it.restores() == 4
	} else {
		assert false, 'apple is not a FoodItem'
	}
}

fn test_block_item_carries_runtime_id() {
	b := BlockItem{
		id:               'minecraft:stone'
		block_runtime_id: 42
	}
	assert b.max_stack_size() == 64
	assert b.placed_block_runtime_id() == 42
}

fn test_unregistered_falls_back_to_64() {
	r := new_registry()
	assert r.max_stack_size('minecraft:totally_unknown') == 64
}

fn test_register_overrides() {
	mut r := new_registry()
	r.register(SimpleItem{
		id:        'minecraft:ender_pearl'
		stack_max: 16
	})
	assert r.max_stack_size('minecraft:ender_pearl') == 16
}
