module block

fn test_wool_carpet_concrete_and_terracotta_colors_registered() {
	r := new_registry()
	suffixes := ['wool', 'carpet', 'concrete', 'terracotta']
	hardnesses := [f32(0.8), 0.1, 1.8, 1.25]
	for color in dye_colors {
		for i, suffix in suffixes {
			id := 'minecraft:${color}_${suffix}'
			b := r.get_by_name(id) or { panic('missing ${id}') }
			assert b.hardness() == hardnesses[i]
		}
	}
	plain := r.get_by_name('minecraft:hardened_clay') or { panic('missing hardened_clay') }
	assert plain.hardness() == 1.25
}

fn test_glazed_terracotta_light_gray_uses_silver_name() {
	r := new_registry()
	silver := glazed_terracotta_block('light_gray', 0)
	assert r.get_by_name('minecraft:silver_glazed_terracotta') != none
	b := r.get(silver.runtime_id()) or { panic('missing silver_glazed_terracotta facing=0') }
	assert b.hardness() == 1.4
}

fn test_glass_and_stained_glass_variants_registered() {
	r := new_registry()
	glass := r.get_by_name('minecraft:glass') or { panic('missing glass') }
	assert glass.hardness() == 0.3
	pane := r.get_by_name('minecraft:glass_pane') or { panic('missing glass_pane') }
	assert pane.hardness() == 0.3
	stained := r.get_by_name('minecraft:blue_stained_glass') or {
		panic('missing blue_stained_glass')
	}
	assert stained.hardness() == 0.3
}

fn test_candle_and_candle_cake_variants_registered() {
	r := new_registry()
	lit := candle_block('red_candle', 3, 1)
	unlit := candle_block('red_candle', 0, 0)
	assert lit.runtime_id() != unlit.runtime_id()
	b := r.get(lit.runtime_id()) or { panic('missing red_candle candles=3 lit=1') }
	assert b.hardness() == 0.1

	cake_lit := candle_cake_block('candle_cake', 1)
	cake_unlit := candle_cake_block('candle_cake', 0)
	assert cake_lit.runtime_id() != cake_unlit.runtime_id()
}

fn test_signs_registered_with_irregular_names() {
	r := new_registry()
	oak_standing := standing_sign_block('oak', 0)
	assert r.get(oak_standing.runtime_id()) != none
	dark_oak_wall := wall_sign_block('dark_oak', 2)
	assert r.get(dark_oak_wall.runtime_id()) != none
	bamboo_standing := standing_sign_block('bamboo', 9)
	b := r.get(bamboo_standing.runtime_id()) or { panic('missing bamboo standing sign') }
	assert b.hardness() == 1.0
}

fn test_banners_and_bed_registered() {
	r := new_registry()
	standing := standing_banner_block(7)
	b := r.get(standing.runtime_id()) or { panic('missing standing_banner direction=7') }
	assert b.hardness() == 1.0
	wall := wall_banner_block(1)
	assert r.get(wall.runtime_id()) != none

	occupied := bed_block(2, 1, 1)
	empty := bed_block(2, 1, 0)
	assert occupied.runtime_id() != empty.runtime_id()
	bed := r.get(empty.runtime_id()) or { panic('missing bed state') }
	assert bed.hardness() == 0.2
}
