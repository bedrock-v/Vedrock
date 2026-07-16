module item

fn test_color_family_items_registered() {
	r := new_registry()
	for color in dye_colors {
		for suffix in ['wool', 'carpet', 'concrete', 'concrete_powder', 'terracotta', 'stained_glass',
			'stained_glass_pane'] {
			id := 'minecraft:${color}_${suffix}'
			it := r.get(id) or { panic('missing ${id}') }
			assert it.block_runtime_id() != 0
		}
	}
	plain := r.get('minecraft:hardened_clay') or { panic('missing hardened_clay') }
	assert plain.block_runtime_id() != 0
	glass := r.get('minecraft:glass') or { panic('missing glass') }
	assert glass.block_runtime_id() != 0
}

fn test_glazed_terracotta_light_gray_uses_silver_name() {
	r := new_registry()
	assert r.get('minecraft:light_gray_glazed_terracotta') == none
	silver := r.get('minecraft:silver_glazed_terracotta') or {
		panic('missing silver_glazed_terracotta')
	}
	assert silver.block_runtime_id() != 0
}

fn test_candles_registered_but_not_candle_cake() {
	r := new_registry()
	candle := r.get('minecraft:candle') or { panic('missing candle') }
	assert candle.block_runtime_id() != 0
	red_candle := r.get('minecraft:red_candle') or { panic('missing red_candle') }
	assert red_candle.block_runtime_id() != 0
	assert r.get('minecraft:candle_cake') == none
}

fn test_signs_registered_with_regular_item_names() {
	r := new_registry()
	for id in ['minecraft:oak_sign', 'minecraft:dark_oak_sign'] {
		it := r.get(id) or { panic('missing ${id}') }
		assert it.block_runtime_id() != 0
	}
}

fn test_banner_and_bed_registered() {
	r := new_registry()
	banner := r.get('minecraft:banner') or { panic('missing banner') }
	assert banner.block_runtime_id() != 0
	bed := r.get('minecraft:bed') or { panic('missing bed') }
	assert bed.block_runtime_id() != 0
}
