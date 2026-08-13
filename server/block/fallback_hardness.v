module block

fn shape_base_hardness(base string) ?f32 {
	return match base {
		'minecraft:oak', 'minecraft:spruce', 'minecraft:birch', 'minecraft:jungle',
		'minecraft:acacia', 'minecraft:dark_oak', 'minecraft:mangrove', 'minecraft:cherry',
		'minecraft:crimson', 'minecraft:warped', 'minecraft:bamboo', 'minecraft:bamboo_mosaic',
		'minecraft:pale_oak' {
			f32(2.0)
		}
		'minecraft:cobblestone', 'minecraft:mossy_cobblestone', 'minecraft:brick',
		'minecraft:smooth_sandstone', 'minecraft:smooth_red_sandstone', 'minecraft:nether_brick',
		'minecraft:red_nether_brick', 'minecraft:smooth_quartz', 'minecraft:polished_blackstone' {
			f32(2.0)
		}
		'minecraft:stone_brick', 'minecraft:mossy_stone_brick', 'minecraft:purpur',
		'minecraft:prismarine', 'minecraft:dark_prismarine', 'minecraft:andesite',
		'minecraft:polished_andesite', 'minecraft:diorite', 'minecraft:polished_diorite',
		'minecraft:granite', 'minecraft:polished_granite', 'minecraft:mud_brick', 'minecraft:tuff',
		'minecraft:polished_tuff', 'minecraft:tuff_brick', 'minecraft:blackstone',
		'minecraft:polished_blackstone_brick' {
			f32(1.5)
		}
		'minecraft:sandstone', 'minecraft:red_sandstone', 'minecraft:cut_sandstone',
		'minecraft:cut_red_sandstone', 'minecraft:quartz' {
			f32(0.8)
		}
		'minecraft:end_brick', 'minecraft:end_stone_brick' {
			f32(3.0)
		}
		'minecraft:deepslate_brick', 'minecraft:deepslate_tile', 'minecraft:cobbled_deepslate',
		'minecraft:polished_deepslate' {
			f32(3.5)
		}
		else {
			none
		}
	}
}

// fallback_hardness maps a palette block name to a family level vanilla break
// hardness for the generic fallback tier. Shape and colour families share one value per family.
fn fallback_hardness(name string) f32 {
	match name {
		'minecraft:iron_door', 'minecraft:iron_trapdoor' {
			return 5.0
		}
		'minecraft:bed' {
			return 0.2
		}
		'minecraft:glass', 'minecraft:glass_pane', 'minecraft:tinted_glass' {
			return 0.3
		}
		'minecraft:beacon' {
			return 3.0
		}
		'minecraft:ancient_debris' {
			return 30.0
		}
		'minecraft:amethyst_block', 'minecraft:budding_amethyst', 'minecraft:amethyst_cluster',
		'minecraft:large_amethyst_bud', 'minecraft:medium_amethyst_bud',
		'minecraft:small_amethyst_bud' {
			return 1.5
		}
		'minecraft:bell', 'minecraft:campfire', 'minecraft:soul_campfire' {
			return 5.0
		}
		'minecraft:chiseled_bookshelf' {
			return 1.5
		}
		'minecraft:netherite_block', 'minecraft:respawn_anchor' {
			return 50.0
		}
		'minecraft:crying_obsidian' {
			return obsidian_hardness
		}
		'minecraft:reinforced_deepslate' {
			return 55.0
		}
		'minecraft:ender_chest' {
			return 22.5
		}
		'minecraft:enchanting_table', 'minecraft:mob_spawner', 'minecraft:spawner',
		'minecraft:iron_bars', 'minecraft:anvil', 'minecraft:chipped_anvil',
		'minecraft:damaged_anvil', 'minecraft:deprecated_anvil', 'minecraft:raw_iron_block',
		'minecraft:raw_gold_block', 'minecraft:raw_copper_block' {
			return 5.0
		}
		'minecraft:web' {
			return 4.0
		}
		'minecraft:furnace', 'minecraft:lit_furnace', 'minecraft:blast_furnace',
		'minecraft:lit_blast_furnace', 'minecraft:smoker', 'minecraft:lit_smoker',
		'minecraft:dispenser', 'minecraft:dropper', 'minecraft:lodestone' {
			return 3.5
		}
		'minecraft:hopper', 'minecraft:observer', 'minecraft:deepslate',
		'minecraft:nether_gold_ore', 'minecraft:quartz_ore' {
			return 3.0
		}
		'minecraft:chest', 'minecraft:trapped_chest', 'minecraft:barrel',
		'minecraft:crafting_table', 'minecraft:cartography_table', 'minecraft:fletching_table',
		'minecraft:smithing_table', 'minecraft:loom' {
			return 2.5
		}
		'minecraft:bookshelf' {
			return 1.5
		}
		'minecraft:ladder' {
			return 0.4
		}
		'minecraft:sea_lantern' {
			return 0.3
		}
		'minecraft:end_portal_frame' {
			return -1.0
		}
		'minecraft:barrier', 'minecraft:border_block', 'minecraft:command_block',
		'minecraft:chain_command_block', 'minecraft:repeating_command_block',
		'minecraft:structure_block', 'minecraft:jigsaw', 'minecraft:deny', 'minecraft:allow' {
			return -1.0
		}
		else {}
	}

	for suffix in ['_stairs', '_double_slab', '_slab', '_wall'] {
		if name.ends_with(suffix) {
			base := name[..name.len - suffix.len]
			if hardness := shape_base_hardness(base) {
				return hardness
			}
			break
		}
	}

	return match true {
		name.contains('copper') { 3.0 }
		name.ends_with('_stairs') { 2.0 }
		name.ends_with('_slab') || name.ends_with('_double_slab') { 2.0 }
		name.ends_with('_wall') { 2.0 }
		name.ends_with('_door') || name.ends_with('_trapdoor') { 3.0 }
		name.ends_with('_fence') || name.ends_with('_fence_gate') { 2.0 }
		name.ends_with('_button') || name.ends_with('_pressure_plate') { 0.5 }
		name.contains('_sign') { 1.0 }
		name.ends_with('_wool') { 0.8 }
		name.ends_with('_carpet') { 0.1 }
		name.ends_with('_concrete') { 1.8 }
		name.ends_with('_concrete_powder') { 0.5 }
		name.ends_with('_glazed_terracotta') { 1.4 }
		name.ends_with('_terracotta') || name == 'minecraft:hardened_clay' { 1.25 }
		name.contains('_stained_glass') { 0.3 }
		name.contains('_candle') { 0.1 }
		name.ends_with('_bed') { 0.2 }
		name.ends_with('_shulker_box') || name == 'minecraft:undyed_shulker_box' { 2.0 }
		name.ends_with('_leaves') || name.contains('_leaves_') { 0.2 }
		name.starts_with('minecraft:infested_') { 0.75 }
		name.contains('deepslate') && name.ends_with('_ore') { 4.5 }
		name.contains('deepslate') { 3.5 }
		name.ends_with('_planks') || name.ends_with('_log') || name.ends_with('_wood') { 2.0 }
		else { 1.0 }
	}
}
