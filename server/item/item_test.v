module item

fn test_default_registry_has_builtins() {
	r := new_registry()
	assert r.len() == 463
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
	assert it is ToolItem
	assert it.durability() == 1561
}

fn test_tool_tiers_have_distinct_mining_speed() {
	r := new_registry()
	wood_pick := r.get('minecraft:wooden_pickaxe') or { panic('missing wooden_pickaxe') }
	netherite_pick := r.get('minecraft:netherite_pickaxe') or { panic('missing netherite_pickaxe') }
	assert wood_pick.mining_speed() == 2.0
	assert netherite_pick.mining_speed() == 9.0
	assert netherite_pick.attack_damage() == 6.0
}

fn test_axe_and_hoe_damage() {
	r := new_registry()
	diamond_axe := r.get('minecraft:diamond_axe') or { panic('missing diamond_axe') }
	assert diamond_axe.attack_damage() == 9.0
	wood_hoe := r.get('minecraft:wooden_hoe') or { panic('missing wooden_hoe') }
	netherite_hoe := r.get('minecraft:netherite_hoe') or { panic('missing netherite_hoe') }
	assert wood_hoe.attack_damage() == 1.0
	assert netherite_hoe.attack_damage() == 1.0
}

fn test_food_saturation() {
	r := new_registry()
	baked_potato := r.get('minecraft:baked_potato') or { panic('missing baked_potato') }
	beetroot := r.get('minecraft:beetroot') or { panic('missing beetroot') }
	assert baked_potato.saturation() == 6.0
	assert beetroot.saturation() == 1.2
}

fn test_armor_carries_defense_and_durability() {
	r := new_registry()
	it := r.get('minecraft:diamond_chestplate') or { panic('missing diamond_chestplate') }
	assert it is ArmorItem
	assert it.armor_points() == 8
	assert it.durability() == 528
	assert it.max_stack_size() == 1
}

fn test_ore_items_and_storage_blocks_registered() {
	r := new_registry()
	raw := r.get('minecraft:raw_iron') or { panic('missing raw_iron') }
	assert raw.max_stack_size() == 64
	ore := r.get('minecraft:diamond_ore') or { panic('missing diamond_ore item') }
	assert ore.block_runtime_id() != 0
	storage := r.get('minecraft:iron_block') or { panic('missing iron_block item') }
	assert storage.block_runtime_id() != 0
}

fn test_stew_does_not_stack() {
	r := new_registry()
	it := r.get('minecraft:mushroom_stew') or { panic('missing mushroom_stew') }
	assert it.max_stack_size() == 1
	assert it.nutrition() == 6
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

fn test_nether_and_end_block_items_registered() {
	r := new_registry()
	soul_sand := r.get('minecraft:soul_sand') or { panic('missing soul_sand item') }
	assert soul_sand is SoulSandItem
	assert soul_sand.block_runtime_id() != 0
	glowstone := r.get('minecraft:glowstone') or { panic('missing glowstone item') }
	assert glowstone is GlowstoneItem
	magma := r.get('minecraft:magma') or { panic('missing magma item') }
	assert magma is MagmaBlockItem
	assert magma.block_runtime_id() != 0
	end_bricks := r.get('minecraft:end_bricks') or { panic('missing end_bricks item') }
	assert end_bricks is EndBricksItem
	purpur := r.get('minecraft:purpur_block') or { panic('missing purpur_block item') }
	assert purpur is PurpurBlockItem
}
