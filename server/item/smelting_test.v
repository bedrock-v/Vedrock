module item

fn test_ores_smelt_into_ingots() {
	recipe := smelting_recipe('minecraft:raw_iron') or {
		assert false, 'raw iron does not smelt'
		return
	}
	assert recipe.output == 'minecraft:iron_ingot'
	assert recipe.experience > 0
}

fn test_food_cooks() {
	for raw, cooked in {
		'minecraft:porkchop': 'minecraft:cooked_porkchop'
		'minecraft:beef':     'minecraft:cooked_beef'
		'minecraft:potato':   'minecraft:baked_potato'
	} {
		recipe := smelting_recipe(raw) or {
			assert false, '${raw} does not cook'
			continue
		}
		assert recipe.output == cooked
	}
}

fn test_most_things_do_not_smelt() {
	if _ := smelting_recipe('minecraft:diamond') {
		assert false, 'a diamond smelted into something'
	}
	if _ := smelting_recipe('minecraft:stick') {
		assert false, 'a stick smelted into something'
	}
}

fn test_fuel_burns_for_its_own_time() {
	assert fuel('minecraft:coal')?.burn_ticks == 1600
	assert fuel('minecraft:coal_block')?.burn_ticks == 16000
	assert fuel('minecraft:lava_bucket')?.burn_ticks == 20000
	assert fuel('minecraft:stick')?.burn_ticks == 100
	// Anything wooden burns for the same short while.
	assert fuel('minecraft:oak_planks')?.burn_ticks == 300
	assert fuel('minecraft:spruce_log')?.burn_ticks == 300
}

fn test_things_that_do_not_burn() {
	if _ := fuel('minecraft:stone') {
		assert false, 'stone burned as fuel'
	}
	if _ := fuel('minecraft:iron_ingot') {
		assert false, 'an iron ingot burned as fuel'
	}
}

// A lava bucket is the one fuel that leaves something behind and burning it
// has to hand the bucket back rather than swallow it.
fn test_a_lava_bucket_leaves_the_bucket() {
	assert fuel('minecraft:lava_bucket')?.residue == 'minecraft:bucket'
	assert fuel('minecraft:coal')?.residue == ''
	assert fuel('minecraft:oak_planks')?.residue == ''
}

fn test_only_wooden_slabs_burn() {
	assert fuel('minecraft:oak_slab')?.burn_ticks == 300
	assert fuel('minecraft:bamboo_mosaic_slab')?.burn_ticks == 300
	for name in ['minecraft:stone_slab', 'minecraft:end_stone_brick_slab',
		'minecraft:petrified_oak_slab', 'minecraft:quartz_slab'] {
		if _ := fuel(name) {
			assert false, '${name} burned as fuel'
		}
	}
}

fn test_recipes_say_which_cooker_takes_them() {
	iron := smelting_recipe('minecraft:raw_iron')?
	assert iron.ores && !iron.food
	beef := smelting_recipe('minecraft:beef')?
	assert beef.food && !beef.ores
	kelp := smelting_recipe('minecraft:kelp')?
	assert kelp.food && !kelp.ores
	sand := smelting_recipe('minecraft:sand')?
	assert !sand.food && !sand.ores
}
