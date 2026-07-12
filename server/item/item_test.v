module item

fn test_default_registry_has_builtins() {
	r := new_registry()
	assert r.len() == 14
}

fn test_registered_blocks_carry_runtime_id() {
	r := new_registry()
	it := r.get('minecraft:stone') or { panic('missing stone') }
	assert it.max_stack_size() == 64
	assert it.block_runtime_id() != 0
	assert it is StoneItem
}

fn test_registered_foods_restore() {
	r := new_registry()
	it := r.get('minecraft:cooked_beef') or { panic('missing cooked_beef') }
	assert it.nutrition() == 8
	assert it is CookedBeefItem
}

fn test_sword_never_stacks() {
	r := new_registry()
	it := r.get('minecraft:diamond_sword') or { panic('missing sword') }
	assert it.max_stack_size() == 1
	assert it.attack_damage() == 7
	assert it is DiamondSwordItem
}

fn test_food_stacks_and_restores() {
	r := new_registry()
	it := r.get('minecraft:apple') or { panic('missing apple') }
	assert it.max_stack_size() == 64
	assert it.nutrition() == 4
	assert it is AppleItem
}

fn test_block_item_carries_runtime_id() {
	b := new_stone_item()
	assert b.max_stack_size() == 64
	assert b.block_runtime_id() != 0
}

fn test_non_weapons_deal_no_damage() {
	r := new_registry()
	it := r.get('minecraft:stick') or { panic('missing stick') }
	assert it.attack_damage() == 0
	assert it is StickItem
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
