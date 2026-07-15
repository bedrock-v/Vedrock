module block

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
		'minecraft:cartography_table' {
			return 2.5
		}
		'minecraft:chiseled_bookshelf' {
			return 1.5
		}
		'minecraft:barrier', 'minecraft:border_block', 'minecraft:command_block',
		'minecraft:chain_command_block', 'minecraft:repeating_command_block',
		'minecraft:structure_block', 'minecraft:jigsaw', 'minecraft:deny', 'minecraft:allow' {
			return -1.0
		}
		else {}
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
		name.contains('deepslate') { 3.5 }
		name.ends_with('_planks') || name.ends_with('_log') || name.ends_with('_wood') { 2.0 }
		else { 1.0 }
	}
}
