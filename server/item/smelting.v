module item

// smelt_ticks is how long a furnace takes to cook one item. A blast furnace or
// a smoker halves it, which is what furnace_speed is for.
pub const smelt_ticks = 200

// SmeltingRecipe is one input turning into one output, and what cooking it is
// worth once the result is taken out.
pub struct SmeltingRecipe {
pub:
	input      string
	output     string
	experience f32
}

// smelting_recipe returns what an item smelts into, or none when it does not
// smelt at all.
pub fn smelting_recipe(input string) ?SmeltingRecipe {
	result, experience := smelting_result(input) or { return none }
	return SmeltingRecipe{
		input:      input
		output:     result
		experience: experience
	}
}

fn smelting_result(input string) ?(string, f32) {
	return match input {
		'minecraft:raw_iron', 'minecraft:iron_ore', 'minecraft:deepslate_iron_ore' {
			'minecraft:iron_ingot', f32(0.7)
		}
		'minecraft:raw_gold', 'minecraft:gold_ore', 'minecraft:deepslate_gold_ore' {
			'minecraft:gold_ingot', f32(1.0)
		}
		'minecraft:raw_copper', 'minecraft:copper_ore', 'minecraft:deepslate_copper_ore' {
			'minecraft:copper_ingot', f32(0.7)
		}
		'minecraft:ancient_debris' {
			'minecraft:netherite_scrap', f32(2.0)
		}
		'minecraft:coal_ore', 'minecraft:deepslate_coal_ore' {
			'minecraft:coal', f32(0.1)
		}
		'minecraft:diamond_ore', 'minecraft:deepslate_diamond_ore' {
			'minecraft:diamond', f32(1.0)
		}
		'minecraft:emerald_ore', 'minecraft:deepslate_emerald_ore' {
			'minecraft:emerald', f32(1.0)
		}
		'minecraft:lapis_ore', 'minecraft:deepslate_lapis_ore' {
			'minecraft:lapis_lazuli', f32(0.2)
		}
		'minecraft:redstone_ore', 'minecraft:deepslate_redstone_ore' {
			'minecraft:redstone', f32(0.7)
		}
		'minecraft:nether_quartz_ore' {
			'minecraft:quartz', f32(0.2)
		}
		'minecraft:sand', 'minecraft:red_sand' {
			'minecraft:glass', f32(0.1)
		}
		'minecraft:cobblestone' {
			'minecraft:stone', f32(0.1)
		}
		'minecraft:stone' {
			'minecraft:smooth_stone', f32(0.1)
		}
		'minecraft:clay_ball' {
			'minecraft:brick', f32(0.3)
		}
		'minecraft:netherrack' {
			'minecraft:netherbrick', f32(0.1)
		}
		'minecraft:cactus' {
			'minecraft:green_dye', f32(1.0)
		}
		'minecraft:kelp' {
			'minecraft:dried_kelp', f32(0.1)
		}
		'minecraft:porkchop' {
			'minecraft:cooked_porkchop', f32(0.35)
		}
		'minecraft:beef' {
			'minecraft:cooked_beef', f32(0.35)
		}
		'minecraft:chicken' {
			'minecraft:cooked_chicken', f32(0.35)
		}
		'minecraft:mutton' {
			'minecraft:cooked_mutton', f32(0.35)
		}
		'minecraft:rabbit' {
			'minecraft:cooked_rabbit', f32(0.35)
		}
		'minecraft:cod' {
			'minecraft:cooked_cod', f32(0.35)
		}
		'minecraft:salmon' {
			'minecraft:cooked_salmon', f32(0.35)
		}
		'minecraft:potato' {
			'minecraft:baked_potato', f32(0.35)
		}
		else {
			none
		}
	}
}

// fuel_burn_ticks is how long an item keeps a furnace lit, or none when it
// does not burn.
pub fn fuel_burn_ticks(name string) ?int {
	if name.ends_with('_planks') || name.ends_with('_log') || name.ends_with('_wood')
		|| name.ends_with('_slab') || name.ends_with('_sapling') {
		return 300
	}
	return match name {
		'minecraft:lava_bucket' { 20000 }
		'minecraft:coal_block' { 16000 }
		'minecraft:blaze_rod' { 2400 }
		'minecraft:coal', 'minecraft:charcoal' { 1600 }
		'minecraft:dried_kelp_block' { 4000 }
		'minecraft:stick' { 100 }
		else { none }
	}
}
