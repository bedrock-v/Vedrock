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
