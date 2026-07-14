module gamedata

import encoding.base64

const oak_planks_b64 = 'CgAAAwoAbmV0d29ya19pZLYai3IECQBuYW1lX2hhc2ilMDLR92rQ4wgEAG5hbWUUAG1pbmVjcmFmdDpvYWtfcGxhbmtzAwcAdmVyc2lvbiE8FQEKBgBzdGF0ZXMAAA=='

fn test_block_network_id_from_nbt() {
	id := block_network_id_from_nbt(base64.decode(oak_planks_b64))!
	assert id == 1921718966
}

fn test_load_game_data() {
	data := load('../data') or { load('data') or { panic('cannot find data dir: ${err}') } }
	assert data.item_entries.len > 1000
	assert data.item_id('minecraft:stone') != 0
	assert data.creative_items.len > 0
	mut has_block := false
	mut potion_metas := []int{}
	for item in data.creative_items {
		if item.block_runtime_id != 0 {
			has_block = true
		}
		if item.numeric_id == data.item_id('minecraft:potion') {
			potion_metas << item.meta
		}
	}
	assert has_block
	// creative_items.json encodes this as "damage".
	assert potion_metas.len > 1
	mut distinct_metas := map[int]bool{}
	for m in potion_metas {
		distinct_metas[m] = true
	}
	assert distinct_metas.len == potion_metas.len
}
