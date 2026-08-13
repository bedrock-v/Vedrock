module block

// fallback_tool maps a palette block name to the tool family and harvest
// level vanilla requires for it, for blocks whose class does not pin its own
// through ToolRequirement. A harvest level of 0 means any tool of that family
// (hands included) harvests the block, it only mines faster with one.
fn fallback_tool(name string) (int, int) {
	match name {
		'minecraft:obsidian', 'minecraft:crying_obsidian', 'minecraft:ancient_debris',
		'minecraft:netherite_block', 'minecraft:respawn_anchor' {
			return tool_type_pickaxe, harvest_level_diamond
		}
		'minecraft:diamond_ore', 'minecraft:deepslate_diamond_ore', 'minecraft:emerald_ore',
		'minecraft:deepslate_emerald_ore', 'minecraft:gold_ore', 'minecraft:deepslate_gold_ore',
		'minecraft:redstone_ore', 'minecraft:lit_redstone_ore', 'minecraft:deepslate_redstone_ore',
		'minecraft:lit_deepslate_redstone_ore', 'minecraft:diamond_block',
		'minecraft:emerald_block', 'minecraft:gold_block', 'minecraft:raw_gold_block' {
			return tool_type_pickaxe, harvest_level_iron
		}
		'minecraft:iron_ore', 'minecraft:deepslate_iron_ore', 'minecraft:lapis_ore',
		'minecraft:deepslate_lapis_ore', 'minecraft:iron_block', 'minecraft:raw_iron_block',
		'minecraft:lapis_block' {
			return tool_type_pickaxe, harvest_level_stone
		}
		'minecraft:coal_ore', 'minecraft:deepslate_coal_ore', 'minecraft:nether_gold_ore',
		'minecraft:quartz_ore', 'minecraft:coal_block', 'minecraft:redstone_block' {
			return tool_type_pickaxe, harvest_level_wood
		}
		'minecraft:ice', 'minecraft:packed_ice', 'minecraft:blue_ice', 'minecraft:frosted_ice',
		'minecraft:magma', 'minecraft:glowstone', 'minecraft:sea_lantern' {
			return tool_type_pickaxe, harvest_level_none
		}
		'minecraft:dirt', 'minecraft:coarse_dirt', 'minecraft:rooted_dirt',
		'minecraft:grass_block', 'minecraft:grass_path', 'minecraft:dirt_with_roots',
		'minecraft:podzol', 'minecraft:mycelium', 'minecraft:farmland', 'minecraft:mud',
		'minecraft:clay', 'minecraft:sand', 'minecraft:red_sand', 'minecraft:gravel',
		'minecraft:suspicious_sand', 'minecraft:suspicious_gravel', 'minecraft:soul_sand',
		'minecraft:soul_soil' {
			return tool_type_shovel, harvest_level_none
		}
		'minecraft:snow', 'minecraft:snow_layer', 'minecraft:powder_snow' {
			// Snow is the one shovel block vanilla refuses to drop by hand.
			return tool_type_shovel, harvest_level_wood
		}
		'minecraft:web' {
			return tool_type_shears | tool_type_sword, harvest_level_none
		}
		'minecraft:hay_block', 'minecraft:target', 'minecraft:dried_kelp_block',
		'minecraft:shroomlight', 'minecraft:nether_wart_block', 'minecraft:warped_wart_block',
		'minecraft:sponge', 'minecraft:wet_sponge' {
			return tool_type_hoe, harvest_level_none
		}
		'minecraft:chest', 'minecraft:trapped_chest', 'minecraft:barrel',
		'minecraft:crafting_table', 'minecraft:bookshelf', 'minecraft:chiseled_bookshelf',
		'minecraft:ladder', 'minecraft:pumpkin', 'minecraft:carved_pumpkin',
		'minecraft:lit_pumpkin', 'minecraft:melon_block', 'minecraft:cartography_table',
		'minecraft:fletching_table', 'minecraft:smithing_table', 'minecraft:loom',
		'minecraft:composter', 'minecraft:beehive', 'minecraft:bee_nest', 'minecraft:campfire',
		'minecraft:soul_campfire', 'minecraft:jukebox', 'minecraft:noteblock',
		'minecraft:bamboo_block' {
			return tool_type_axe, harvest_level_none
		}
		'minecraft:glass', 'minecraft:glass_pane', 'minecraft:tinted_glass', 'minecraft:beacon',
		'minecraft:sculk_sensor', 'minecraft:slime', 'minecraft:honey_block' {
			return tool_type_none, harvest_level_none
		}
		else {}
	}

	if name.contains('copper') {
		return tool_type_pickaxe, harvest_level_stone
	}
	if name.ends_with('_leaves') || name.contains('_leaves_') {
		return tool_type_shears | tool_type_hoe | tool_type_sword, harvest_level_none
	}
	if name.ends_with('_wool') || name.ends_with('_carpet') {
		return tool_type_shears, harvest_level_none
	}
	if name.ends_with('_concrete_powder') {
		return tool_type_shovel, harvest_level_none
	}
	if name.contains('_log') || name.contains('_wood') || name.contains('_stem')
		|| name.contains('_hyphae') || name.contains('_planks') || name.contains('_sign')
		|| name.ends_with('_fence') || name.ends_with('_fence_gate')
		|| name.ends_with('_shulker_box') || name == 'minecraft:undyed_shulker_box' {
		return tool_type_axe, harvest_level_none
	}
	if name.ends_with('_door') || name.ends_with('_trapdoor') || name.ends_with('_button')
		|| name.ends_with('_pressure_plate') {
		if name.starts_with('minecraft:iron_') || name.starts_with('minecraft:polished_blackstone_')
			|| name.starts_with('minecraft:heavy_') || name.starts_with('minecraft:light_weighted_') {
			return tool_type_pickaxe, harvest_level_wood
		}
		return tool_type_axe, harvest_level_none
	}
	if is_stone_shape(name) {
		return tool_type_pickaxe, harvest_level_wood
	}
	return tool_type_none, harvest_level_none
}

// is_stone_shape reports whether the name belongs to the stone family, which
// vanilla mines with a pickaxe. Wooden shapes are already handled before this
// runs, so shape suffixes alone are enough here.
fn is_stone_shape(name string) bool {
	for word in ['stone', 'cobble', 'deepslate', 'andesite', 'diorite', 'granite', 'tuff', 'calcite',
		'basalt', 'blackstone', 'sandstone', 'brick', 'quartz', 'purpur', 'prismarine', 'terracotta',
		'concrete', 'amethyst', 'dripstone', 'netherrack', 'nether_brick', 'anvil', 'furnace',
		'hopper', 'cauldron', 'rail', 'piston', 'observer', 'dispenser', 'dropper', 'lantern',
		'chain', 'bell', 'grindstone', 'stonecutter', 'smoker', 'blast_furnace', 'enchanting_table',
		'brewing_stand', 'end_stone', 'end_bricks', 'bedrock', 'ore'] {
		if name.contains(word) {
			return true
		}
	}
	return name.ends_with('_slab') || name.ends_with('_stairs') || name.ends_with('_wall')
}
