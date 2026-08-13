module block

fn info_for(name string) BreakInfo {
	r := new_registry()
	b := r.get_by_name(name) or { panic('${name} is not registered') }
	return r.break_info(b.runtime_id())
}

fn assert_seconds(got f32, want f32) {
	assert got > want - 0.001 && got < want + 0.001
}

fn test_stone_needs_a_pickaxe() {
	info := info_for('minecraft:stone')
	assert info.tool_type == tool_type_pickaxe
	assert info.harvest_level == harvest_level_wood
	// Bare hands never harvest stone, so the slow multiplier applies.
	assert_seconds(info.break_seconds(tool_type_none, harvest_level_none, 1.0), 7.5)
	assert_seconds(info.break_seconds(tool_type_pickaxe, harvest_level_wood, 2.0), 1.125)
	assert_seconds(info.break_seconds(tool_type_pickaxe, harvest_level_diamond, 8.0), 0.28125)
}

fn test_planks_are_harvested_by_hand() {
	info := info_for('minecraft:oak_planks')
	assert info.tool_type == tool_type_axe
	assert info.harvest_level == harvest_level_none
	assert_seconds(info.break_seconds(tool_type_none, harvest_level_none, 1.0), 3.0)
	assert_seconds(info.break_seconds(tool_type_axe, harvest_level_iron, 6.0), 0.5)
}

fn test_dirt_is_shovel_work() {
	info := info_for('minecraft:dirt')
	assert info.tool_type == tool_type_shovel
	assert_seconds(info.break_seconds(tool_type_none, harvest_level_none, 1.0), 0.75)
	assert_seconds(info.break_seconds(tool_type_shovel, harvest_level_iron, 6.0), 0.125)
	// A pickaxe is the wrong family, so its efficiency does not count.
	assert_seconds(info.break_seconds(tool_type_pickaxe, harvest_level_diamond, 8.0), 0.75)
}

fn test_obsidian_needs_a_diamond_pickaxe() {
	info := info_for('minecraft:obsidian')
	assert info.harvest_level == harvest_level_diamond
	assert_seconds(info.break_seconds(tool_type_pickaxe, harvest_level_iron, 6.0), 41.666668)
	assert_seconds(info.break_seconds(tool_type_pickaxe, harvest_level_diamond, 8.0), 9.375)
}

fn test_bedrock_is_unbreakable() {
	info := info_for('minecraft:bedrock')
	assert !info.breakable()
	assert !info.tool_compatible(tool_type_pickaxe, harvest_level_netherite)
}

// Blocks with no modelled class take their hardness from the name fallback.
// Before these entries existed they all landed on the generic 1.0, which broke
// hard blocks in a fraction of the vanilla time.
fn test_fallback_hardness_covers_hard_blocks() {
	assert fallback_hardness('minecraft:netherite_block') == 50.0
	assert fallback_hardness('minecraft:crying_obsidian') == 50.0
	assert fallback_hardness('minecraft:respawn_anchor') == 50.0
	assert fallback_hardness('minecraft:ender_chest') == 22.5
	assert fallback_hardness('minecraft:enchanting_table') == 5.0
	assert fallback_hardness('minecraft:web') == 4.0
	assert fallback_hardness('minecraft:furnace') == 3.5
	assert fallback_hardness('minecraft:hopper') == 3.0
	assert fallback_hardness('minecraft:nether_gold_ore') == 3.0
	assert fallback_hardness('minecraft:chest') == 2.5
	assert fallback_hardness('minecraft:ladder') == 0.4
	assert fallback_hardness('minecraft:end_portal_frame') < 0
}

// Deepslate ores are harder than the deepslate they sit in, so the ore rule
// has to win over the generic deepslate family value.
fn test_deepslate_ores_are_harder_than_deepslate() {
	assert fallback_hardness('minecraft:deepslate_diamond_ore') == 4.5
	assert fallback_hardness('minecraft:lit_deepslate_redstone_ore') == 4.5
	assert fallback_hardness('minecraft:deepslate') == 3.0
	assert fallback_hardness('minecraft:deepslate_bricks') == 3.5
}

fn test_unregistered_ids_fall_back_to_a_plain_block() {
	r := new_registry()
	info := r.break_info(123456789)
	assert info.hardness == 1.0
	assert info.tool_type == tool_type_none
	assert_seconds(info.break_seconds(tool_type_none, harvest_level_none, 1.0), 1.5)
}
