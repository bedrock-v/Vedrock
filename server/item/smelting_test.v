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
	assert fuel_burn_ticks('minecraft:coal')? == 1600
	assert fuel_burn_ticks('minecraft:coal_block')? == 16000
	assert fuel_burn_ticks('minecraft:lava_bucket')? == 20000
	assert fuel_burn_ticks('minecraft:stick')? == 100
	// Anything wooden burns for the same short while.
	assert fuel_burn_ticks('minecraft:oak_planks')? == 300
	assert fuel_burn_ticks('minecraft:spruce_log')? == 300
}

fn test_things_that_do_not_burn() {
	if _ := fuel_burn_ticks('minecraft:stone') {
		assert false, 'stone burned as fuel'
	}
	if _ := fuel_burn_ticks('minecraft:iron_ingot') {
		assert false, 'an iron ingot burned as fuel'
	}
}
