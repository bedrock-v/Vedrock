module block

import server.world

fn test_default_registry_has_builtins() {
	r := new_registry()
	assert r.len() == 400
}

fn test_registered_blocks_found_by_runtime_and_name() {
	r := new_registry()
	by_name := r.get_by_name('minecraft:stone') or { panic('missing stone by name') }
	by_runtime := r.get(world.stone.network_id) or { panic('missing stone by runtime id') }
	assert by_name.identifier() == by_runtime.identifier()
	assert by_name.runtime_id() == world.stone.network_id
}

fn test_bedrock_is_unbreakable() {
	r := new_registry()
	b := r.get_by_name('minecraft:bedrock') or { panic('missing bedrock') }
	assert !b.breakable()
	assert b.hardness() < 0
	assert b is BedrockBlock
	assert !r.breakable(world.bedrock.network_id)
}

fn test_simple_blocks_are_breakable() {
	r := new_registry()
	b := r.get_by_name('minecraft:dirt') or { panic('missing dirt') }
	assert b.breakable()
	assert b.hardness() == 0.5
	assert b is DirtBlock
}

fn test_unregistered_falls_back_to_breakable() {
	r := new_registry()
	assert r.breakable(123456789)
	assert r.hardness(123456789) == 1.0
}

fn test_register_overrides() {
	mut r := new_registry()
	r.register(UnbreakableBlock{
		id:            'minecraft:dirt'
		block_runtime: world.dirt.network_id
	})
	assert !r.breakable(world.dirt.network_id)
}

fn test_stone_found_as_own_class() {
	r := new_registry()
	b := r.get_by_name('minecraft:stone') or { panic('missing stone') }
	assert b is StoneBlock
	assert b.hardness() == 1.5
}

fn test_ore_and_storage_blocks_registered() {
	r := new_registry()
	ore := r.get_by_name('minecraft:diamond_ore') or { panic('missing diamond_ore') }
	assert ore is DiamondOreBlock
	assert ore.hardness() == 3.0
	storage := r.get_by_name('minecraft:diamond_block') or { panic('missing diamond_block') }
	assert storage is DiamondBlock
	assert storage.hardness() == 5.0
}

fn test_obsidian_is_hard_to_break() {
	r := new_registry()
	b := r.get_by_name('minecraft:obsidian') or { panic('missing obsidian') }
	assert b.hardness() == 50.0
	assert b.breakable()
}

fn test_softer_storage_blocks_are_not_uniformly_5() {
	r := new_registry()
	gold := r.get_by_name('minecraft:gold_block') or { panic('missing gold_block') }
	lapis := r.get_by_name('minecraft:lapis_block') or { panic('missing lapis_block') }
	copper := r.get_by_name('minecraft:copper_block') or { panic('missing copper_block') }
	iron := r.get_by_name('minecraft:iron_block') or { panic('missing iron_block') }
	assert gold.hardness() == 3.0
	assert lapis.hardness() == 3.0
	assert copper.hardness() == 3.0
	assert iron.hardness() == 5.0
}

fn test_snow_block_hardness() {
	r := new_registry()
	b := r.get_by_name('minecraft:snow') or { panic('missing snow') }
	assert b.hardness() == 0.2
}

fn test_register_fallbacks_covers_unmodeled_names() {
	mut r := new_registry()
	before := r.len()
	r.register_fallbacks([
		PaletteEntry{'minecraft:oak_stairs', 5001},
		PaletteEntry{'minecraft:oak_stairs', 5002},
		PaletteEntry{'minecraft:beacon', 5003},
	])
	assert r.len() == before + 2
	stairs := r.get_by_name('minecraft:oak_stairs') or { panic('missing fallback stairs') }
	// Canonical form is the first palette state of the name.
	assert stairs.runtime_id() == 5001
	assert stairs.breakable()
	// Family hardness table: stairs break at 2.0, not the 1.0 default.
	assert stairs.hardness() == 2.0
	// Every state id resolves for hardness lookups, not just the canonical one.
	assert r.get(5002) or { panic('missing state alias') }.identifier() == 'minecraft:oak_stairs'
	assert r.get(5003) or { panic('missing beacon') }.identifier() == 'minecraft:beacon'
}

fn test_fallback_hardness_by_family() {
	mut r := new_registry()
	r.register_fallbacks([
		PaletteEntry{'minecraft:oak_stairs', 1},
		PaletteEntry{'minecraft:cobblestone_wall', 2},
		PaletteEntry{'minecraft:spruce_door', 3},
		PaletteEntry{'minecraft:iron_door', 4},
		PaletteEntry{'minecraft:oxidized_cut_copper_stairs', 5},
		PaletteEntry{'minecraft:red_wool', 6},
		PaletteEntry{'minecraft:lime_carpet', 7},
		PaletteEntry{'minecraft:cyan_terracotta', 8},
		PaletteEntry{'minecraft:infested_stone', 9},
		PaletteEntry{'minecraft:deepslate_tiles', 10},
		PaletteEntry{'minecraft:beacon', 11},
		PaletteEntry{'minecraft:ancient_debris', 12},
		PaletteEntry{'minecraft:amethyst_block', 13},
		PaletteEntry{'minecraft:budding_amethyst', 14},
		PaletteEntry{'minecraft:bell', 15},
		PaletteEntry{'minecraft:campfire', 16},
		PaletteEntry{'minecraft:cartography_table', 17},
		PaletteEntry{'minecraft:chiseled_bookshelf', 18},
		PaletteEntry{'minecraft:command_block', 19},
		PaletteEntry{'minecraft:chain_command_block', 20},
		PaletteEntry{'minecraft:structure_block', 21},
		PaletteEntry{'minecraft:jigsaw', 22},
		PaletteEntry{'minecraft:border_block', 23},
	])
	assert r.hardness(1) == 2.0
	assert r.hardness(2) == 2.0
	assert r.hardness(3) == 3.0
	// Family exception: iron doors are 5.0, not the wood door 3.0.
	assert r.hardness(4) == 5.0
	// Copper wins over the _stairs suffix.
	assert r.hardness(5) == 3.0
	assert r.hardness(6) == 0.8
	assert r.hardness(7) == 0.1
	assert r.hardness(8) == 1.25
	assert r.hardness(9) == 0.75
	assert r.hardness(10) == 3.5
	assert r.hardness(11) == 3.0
	assert r.hardness(12) == 30.0
	assert r.hardness(13) == 1.5
	assert r.hardness(14) == 1.5
	assert r.hardness(15) == 5.0
	assert r.hardness(16) == 5.0
	assert r.hardness(17) == 2.5
	assert r.hardness(18) == 1.5
	for runtime_id in [19, 20, 21, 22, 23] {
		assert !r.breakable(runtime_id)
		assert r.hardness(runtime_id) < 0
	}
}

fn test_register_fallbacks_never_clobbers_hand_classes() {
	mut r := new_registry()
	r.register_fallbacks([
		PaletteEntry{'minecraft:bedrock', 7001},
		PaletteEntry{'minecraft:bedrock', 7002},
	])
	b := r.get_by_name('minecraft:bedrock') or { panic('missing bedrock') }
	assert b is BedrockBlock
	assert !b.breakable()

	extra := r.get(7002) or { panic('missing extra bedrock state') }
	assert extra is BedrockBlock
	assert !r.breakable(7002)
}

fn test_nether_and_end_blocks_registered() {
	r := new_registry()
	soul_sand := r.get_by_name('minecraft:soul_sand') or { panic('missing soul_sand') }
	assert soul_sand is SoulSandBlock
	assert soul_sand.hardness() == 0.5
	soul_soil := r.get_by_name('minecraft:soul_soil') or { panic('missing soul_soil') }
	assert soul_soil is SoulSoilBlock
	glowstone := r.get_by_name('minecraft:glowstone') or { panic('missing glowstone') }
	assert glowstone is GlowstoneBlock
	assert glowstone.hardness() == 0.3
	magma := r.get_by_name('minecraft:magma') or { panic('missing magma') }
	assert magma is MagmaBlock
	assert magma.hardness() == 0.5
	end_bricks := r.get_by_name('minecraft:end_bricks') or { panic('missing end_bricks') }
	assert end_bricks is EndBricksBlock
	purpur := r.get_by_name('minecraft:purpur_block') or { panic('missing purpur_block') }
	assert purpur is PurpurBlock
	assert purpur.hardness() == 1.5
}
