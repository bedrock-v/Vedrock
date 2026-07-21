module item

fn test_default_registry_has_builtins() {
	r := new_registry()
	assert r.len() == 488
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
	assert it.attack_damage() == 8
	assert it is ToolItem
	assert it.durability() == 1561
}

fn test_tool_tiers_have_distinct_mining_speed() {
	r := new_registry()
	wood_pick := r.get('minecraft:wooden_pickaxe') or { panic('missing wooden_pickaxe') }
	netherite_pick := r.get('minecraft:netherite_pickaxe') or { panic('missing netherite_pickaxe') }
	assert wood_pick.mining_speed() == 2.0
	assert netherite_pick.mining_speed() == 9.0
	assert netherite_pick.attack_damage() == 7.0
}

fn test_axe_and_hoe_damage() {
	r := new_registry()
	diamond_axe := r.get('minecraft:diamond_axe') or { panic('missing diamond_axe') }
	assert diamond_axe.attack_damage() == 7.0
	wood_hoe := r.get('minecraft:wooden_hoe') or { panic('missing wooden_hoe') }
	netherite_hoe := r.get('minecraft:netherite_hoe') or { panic('missing netherite_hoe') }
	assert wood_hoe.attack_damage() == 3.0
	assert netherite_hoe.attack_damage() == 7.0
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

fn test_copper_tools_have_real_stats() {
	r := new_registry()
	sword := r.get('minecraft:copper_sword') or { panic('missing copper_sword') }
	pick := r.get('minecraft:copper_pickaxe') or { panic('missing copper_pickaxe') }
	axe := r.get('minecraft:copper_axe') or { panic('missing copper_axe') }
	assert sword is ToolItem
	assert sword.max_stack_size() == 1
	assert sword.durability() == 190
	assert sword.attack_damage() == 6.0
	assert pick.durability() == 190
	assert pick.attack_damage() == 4.0
	assert axe.durability() == 190
	assert axe.attack_damage() == 5.0
}

fn test_copper_armor_has_real_stats() {
	r := new_registry()
	helmet := r.get('minecraft:copper_helmet') or { panic('missing copper_helmet') }
	chestplate := r.get('minecraft:copper_chestplate') or { panic('missing copper_chestplate') }
	leggings := r.get('minecraft:copper_leggings') or { panic('missing copper_leggings') }
	boots := r.get('minecraft:copper_boots') or { panic('missing copper_boots') }
	assert helmet is ArmorItem
	assert helmet.armor_points() == 2
	assert helmet.durability() == 122
	assert chestplate.armor_points() == 4
	assert chestplate.durability() == 177
	assert leggings.armor_points() == 3
	assert leggings.durability() == 166
	assert boots.armor_points() == 1
	assert boots.durability() == 143
}

fn test_tail_foods_restore_real_values() {
	r := new_registry()
	rabbit := r.get('minecraft:rabbit') or { panic('missing rabbit') }
	cooked_rabbit := r.get('minecraft:cooked_rabbit') or { panic('missing cooked_rabbit') }
	suspicious_stew := r.get('minecraft:suspicious_stew') or { panic('missing suspicious_stew') }
	chorus := r.get('minecraft:chorus_fruit') or { panic('missing chorus_fruit') }
	pufferfish := r.get('minecraft:pufferfish') or { panic('missing pufferfish') }
	tropical_fish := r.get('minecraft:tropical_fish') or { panic('missing tropical_fish') }
	rotten_flesh := r.get('minecraft:rotten_flesh') or { panic('missing rotten_flesh') }
	spider_eye := r.get('minecraft:spider_eye') or { panic('missing spider_eye') }
	enchanted_apple := r.get('minecraft:enchanted_golden_apple') or {
		panic('missing enchanted_golden_apple')
	}
	assert rabbit.nutrition() == 3
	assert rabbit.saturation() == 1.8
	assert cooked_rabbit.nutrition() == 5
	assert cooked_rabbit.saturation() == 6.0
	assert suspicious_stew.max_stack_size() == 1
	assert suspicious_stew.nutrition() == 6
	assert suspicious_stew.saturation() == 7.2
	assert chorus.nutrition() == 4
	assert chorus.saturation() == 2.4
	assert pufferfish.nutrition() == 1
	assert pufferfish.saturation() == 0.2
	assert tropical_fish.nutrition() == 1
	assert tropical_fish.saturation() == 0.2
	assert rotten_flesh.nutrition() == 4
	assert rotten_flesh.saturation() == 0.8
	assert spider_eye.nutrition() == 2
	assert spider_eye.saturation() == 3.2
	assert enchanted_apple.nutrition() == 4
	assert enchanted_apple.saturation() == 9.6
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

fn test_register_fallbacks_covers_unmodeled_items() {
	mut r := new_registry()
	before := r.len()
	r.register_fallbacks([
		FallbackEntry{'minecraft:oak_stairs', 5001},
		FallbackEntry{'minecraft:amethyst_shard', 0},
	])
	assert r.len() == before + 2
	stairs := r.get('minecraft:oak_stairs') or { panic('missing fallback stairs item') }
	assert stairs.block_runtime_id() == 5001
	assert stairs.max_stack_size() == 64
	shard := r.get('minecraft:amethyst_shard') or { panic('missing fallback shard') }
	assert shard.block_runtime_id() == 0
	assert shard.max_stack_size() == 64
}

fn test_fallback_stack_sizes_by_family() {
	mut r := new_registry()
	r.register_fallbacks([
		FallbackEntry{'minecraft:oak_boat', 0},
		FallbackEntry{'minecraft:minecart', 0},
		FallbackEntry{'minecraft:chest_minecart', 0},
		FallbackEntry{'minecraft:lava_bucket', 0},
		FallbackEntry{'minecraft:bucket', 0},
		FallbackEntry{'minecraft:splash_potion', 0},
		FallbackEntry{'minecraft:music_disc_cat', 0},
		FallbackEntry{'minecraft:bundle', 0},
		FallbackEntry{'minecraft:white_bundle', 0},
		FallbackEntry{'minecraft:white_harness', 0},
		FallbackEntry{'minecraft:mojang_banner_pattern', 0},
		FallbackEntry{'minecraft:elytra', 0},
		FallbackEntry{'minecraft:oak_sign', 0},
		FallbackEntry{'minecraft:red_banner', 0},
		FallbackEntry{'minecraft:ender_pearl', 0},
		FallbackEntry{'minecraft:red_bed', 4242},
		FallbackEntry{'minecraft:amethyst_shard', 0},
	])
	assert r.max_stack_size('minecraft:oak_boat') == 1
	assert r.max_stack_size('minecraft:minecart') == 1
	assert r.max_stack_size('minecraft:chest_minecart') == 1
	assert r.max_stack_size('minecraft:lava_bucket') == 1
	// Only the empty bucket stacks.
	assert r.max_stack_size('minecraft:bucket') == 16
	assert r.max_stack_size('minecraft:splash_potion') == 1
	assert r.max_stack_size('minecraft:music_disc_cat') == 1
	assert r.max_stack_size('minecraft:bundle') == 1
	assert r.max_stack_size('minecraft:white_bundle') == 1
	assert r.max_stack_size('minecraft:white_harness') == 1
	assert r.max_stack_size('minecraft:mojang_banner_pattern') == 1
	assert r.max_stack_size('minecraft:elytra') == 1
	// oak_sign is hand-registered by decorative components (also 16), so use
	// an unmodeled sign name to prove the fallback suffix rule.
	assert r.max_stack_size('minecraft:oak_sign') == 16
	assert r.max_stack_size('minecraft:bamboo_sign') == 16
	assert r.max_stack_size('minecraft:red_banner') == 16
	assert r.max_stack_size('minecraft:ender_pearl') == 16
	// Stack overrides apply to block-items too, not just plain items.
	bed := r.get('minecraft:red_bed') or { panic('missing bed') }
	assert bed.max_stack_size() == 1
	assert bed.block_runtime_id() == 4242
	assert r.max_stack_size('minecraft:amethyst_shard') == 64
}

fn test_register_fallbacks_never_clobbers_hand_items() {
	mut r := new_registry()
	r.register_fallbacks([
		FallbackEntry{'minecraft:diamond_sword', 0},
	])
	sword := r.get('minecraft:diamond_sword') or { panic('missing sword') }
	assert sword.max_stack_size() == 1
	assert sword.attack_damage() == 8
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

fn test_goat_horn_use_result_by_meta() {
	r := new_registry()
	horn := r.get('minecraft:goat_horn') or { panic('missing goat_horn') }
	assert horn is GoatHornItem
	assert horn.max_stack_size() == 1

	ponder := r.use_result('minecraft:goat_horn', 0) or { panic('missing use_result for meta 0') }
	assert ponder.sound == 'item.goat_horn.sound.0'
	dream := r.use_result('minecraft:goat_horn', 7) or { panic('missing use_result for meta 7') }
	assert dream.sound == 'item.goat_horn.sound.7'

	// Out-of-range meta falls back to the first sound rather than panicking.
	clamped := r.use_result('minecraft:goat_horn', 99) or {
		panic('missing use_result for out-of-range meta')
	}
	assert clamped.sound == 'item.goat_horn.sound.0'

	// Items without a UseableItem implementation have no use_result.
	assert r.use_result('minecraft:stone', 0) == none
}

fn test_compass_family_has_dedicated_classes() {
	r := new_registry()
	compass := r.get('minecraft:compass') or { panic('missing compass') }
	assert compass is CompassItem
	assert compass.max_stack_size() == 64
	recovery := r.get('minecraft:recovery_compass') or { panic('missing recovery_compass') }
	assert recovery is RecoveryCompassItem
	lodestone := r.get('minecraft:lodestone_compass') or { panic('missing lodestone_compass') }
	assert lodestone is LodestoneCompassItem
}

fn test_bone_meal_advances_only_crop_growth() {
	r := new_registry()
	bone_meal := r.get('minecraft:bone_meal') or { panic('missing bone_meal') }
	assert bone_meal is BoneMealItem

	result := r.use_on_block_result('minecraft:bone_meal', 'minecraft:wheat', 0) or {
		panic('expected bone meal to act on wheat')
	}
	assert result.state_key == 'growth'
	assert result.state_delta == 1

	// Not every block is bone mealable.
	assert r.use_on_block_result('minecraft:bone_meal', 'minecraft:stone', 0) == none
	// Not every item is a UsableOnBlockItem.
	assert r.use_on_block_result('minecraft:stone', 'minecraft:wheat', 0) == none
}

fn test_goat_horn_has_a_cooldown() {
	r := new_registry()
	ticks := r.cooldown_ticks('minecraft:goat_horn') or { panic('expected a cooldown') }
	assert ticks > 0
	// Items without a CooldownItem implementation have no cooldown.
	assert r.cooldown_ticks('minecraft:stone') == none
}

fn test_damage_item_breaks_a_tool_at_max_durability() {
	pick := new_tool_item(ToolTier.wood, ToolType.pickaxe)
	max := pick.durability()
	assert max > 0

	// Two points below max: damaged, not broken.
	result := damage_item(pick, max - 2, 1)
	assert !result.broken
	assert result.new_meta == max - 1

	// Reaches max: broken.
	broken := damage_item(pick, max - 1, 1)
	assert broken.broken
}

fn test_damage_item_is_a_noop_for_non_durable_items() {
	stone := new_stone_item()
	result := damage_item(stone, 0, 100)
	assert !result.broken
	assert result.new_meta == 0
}

fn test_crops_compost_on_a_composter_but_do_nothing_elsewhere() {
	r := new_registry()
	for id in ['minecraft:wheat', 'minecraft:carrot', 'minecraft:potato', 'minecraft:beetroot'] {
		result := r.use_on_block_result(id, 'minecraft:composter', 0) or {
			panic('expected ${id} to compost')
		}
		assert result.state_key == 'composter_fill_level'
		assert result.state_delta == 1
		assert r.use_on_block_result(id, 'minecraft:stone', 0) == none
	}
	// Not every item composts.
	assert r.use_on_block_result('minecraft:stone', 'minecraft:composter', 0) == none
}
