module session

import server.internal.gamedata

fn load_test_data() gamedata.GameData {
	return gamedata.load('../data') or {
		gamedata.load('data') or { panic('cannot find data dir: ${err}') }
	}
}

fn test_long_tail_resolves_from_palette_fallbacks() {
	data := load_test_data()
	mut hub := new_hub(data)
	for name in [
		'minecraft:beacon',
		'minecraft:bell',
		'minecraft:campfire',
		'minecraft:cartography_table',
		'minecraft:chiseled_bookshelf',
		'minecraft:ancient_debris',
		'minecraft:amethyst_block',
		'minecraft:command_block',
		'minecraft:structure_block',
		'minecraft:jigsaw',
		'minecraft:border_block',
		'minecraft:reserved6',
	] {
		b := hub.blocks.get_by_name(name) or { panic('missing block fallback ${name}') }
		assert b.identifier() == name
		assert b.runtime_id() != 0
	}
	for name in [
		'minecraft:amethyst_shard',
		'minecraft:white_dye',
		'minecraft:mojang_banner_pattern',
		'minecraft:netherite_upgrade_smithing_template',
		'minecraft:bundle',
		'minecraft:white_bundle',
		'minecraft:white_harness',
		'minecraft:minecart',
		'minecraft:elytra',
	] {
		it := hub.items.get(name) or { panic('missing item fallback ${name}') }
		assert it.identifier() == name
		assert it.block_runtime_id() == 0
	}
	for name in ['minecraft:beacon', 'minecraft:command_block'] {
		it := hub.items.get(name) or { panic('missing block-item fallback ${name}') }
		assert it.identifier() == name
		assert it.block_runtime_id() != 0
	}
}
