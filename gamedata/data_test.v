module gamedata

import encoding.base64

const oak_planks_b64 = 'CgAAAwoAbmV0d29ya19pZLYai3IECQBuYW1lX2hhc2ilMDLR92rQ4wgEAG5hbWUUAG1pbmVjcmFmdDpvYWtfcGxhbmtzAwcAdmVyc2lvbiE8FQEKBgBzdGF0ZXMAAA=='

fn test_block_network_id_from_nbt() {
	id := block_network_id_from_nbt(base64.decode(oak_planks_b64))!
	assert id == 1921718966
}

fn test_load_game_data() {
	data := load('../data') or {
		load('data') or { panic('cannot find data dir: ${err}') }
	}
	assert data.item_entries.len > 1000
	assert data.item_id('minecraft:stone') != 0
	assert data.creative_items.len > 0
	mut has_block := false
	for item in data.creative_items {
		if item.block_runtime_id != 0 {
			has_block = true
			break
		}
	}
	assert has_block
}
