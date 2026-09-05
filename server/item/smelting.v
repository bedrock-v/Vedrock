module item

// SmeltingRecipe is one input turning into one output, and what cooking it is
// worth once the result is taken out.
//
// food and ores say which of the two faster cookers will take it: a smoker
// only cooks food and a blast furnace only ores while a plain furnace takes
// everything.
pub struct SmeltingRecipe {
pub:
	input      string
	output     string
	experience f32
	food       bool
	ores       bool
}

// smelting_recipe returns what an item smelts into, or none when it does not
// smelt at all.
pub fn smelting_recipe(input string) ?SmeltingRecipe {
	result, experience, food, ores := smelting_result(input) or { return none }
	return SmeltingRecipe{
		input:      input
		output:     result
		experience: experience
		food:       food
		ores:       ores
	}
}

fn smelting_result(input string) ?(string, f32, bool, bool) {
	return match input {
		'minecraft:raw_iron', 'minecraft:iron_ore', 'minecraft:deepslate_iron_ore' {
			'minecraft:iron_ingot', f32(0.7), false, true
		}
		'minecraft:raw_gold', 'minecraft:gold_ore', 'minecraft:deepslate_gold_ore' {
			'minecraft:gold_ingot', f32(1.0), false, true
		}
		'minecraft:raw_copper', 'minecraft:copper_ore', 'minecraft:deepslate_copper_ore' {
			'minecraft:copper_ingot', f32(0.7), false, true
		}
		'minecraft:ancient_debris' {
			'minecraft:netherite_scrap', f32(2.0), false, true
		}
		'minecraft:coal_ore', 'minecraft:deepslate_coal_ore' {
			'minecraft:coal', f32(0.1), false, true
		}
		'minecraft:diamond_ore', 'minecraft:deepslate_diamond_ore' {
			'minecraft:diamond', f32(1.0), false, true
		}
		'minecraft:emerald_ore', 'minecraft:deepslate_emerald_ore' {
			'minecraft:emerald', f32(1.0), false, true
		}
		'minecraft:lapis_ore', 'minecraft:deepslate_lapis_ore' {
			'minecraft:lapis_lazuli', f32(0.2), false, true
		}
		'minecraft:redstone_ore', 'minecraft:deepslate_redstone_ore' {
			'minecraft:redstone', f32(0.7), false, true
		}
		'minecraft:nether_quartz_ore' {
			'minecraft:quartz', f32(0.2), false, true
		}
		'minecraft:sand', 'minecraft:red_sand' {
			'minecraft:glass', f32(0.1), false, false
		}
		'minecraft:cobblestone' {
			'minecraft:stone', f32(0.1), false, false
		}
		'minecraft:stone' {
			'minecraft:smooth_stone', f32(0.1), false, false
		}
		'minecraft:clay_ball' {
			'minecraft:brick', f32(0.3), false, false
		}
		'minecraft:netherrack' {
			'minecraft:netherbrick', f32(0.1), false, false
		}
		'minecraft:cactus' {
			'minecraft:green_dye', f32(1.0), false, false
		}
		'minecraft:kelp' {
			'minecraft:dried_kelp', f32(0.1), true, false
		}
		'minecraft:porkchop' {
			'minecraft:cooked_porkchop', f32(0.35), true, false
		}
		'minecraft:beef' {
			'minecraft:cooked_beef', f32(0.35), true, false
		}
		'minecraft:chicken' {
			'minecraft:cooked_chicken', f32(0.35), true, false
		}
		'minecraft:mutton' {
			'minecraft:cooked_mutton', f32(0.35), true, false
		}
		'minecraft:rabbit' {
			'minecraft:cooked_rabbit', f32(0.35), true, false
		}
		'minecraft:cod' {
			'minecraft:cooked_cod', f32(0.35), true, false
		}
		'minecraft:salmon' {
			'minecraft:cooked_salmon', f32(0.35), true, false
		}
		'minecraft:potato' {
			'minecraft:baked_potato', f32(0.35), true, false
		}
		else {
			none
		}
	}
}

// wood_types are the tree materials whose worked forms burn. The suffix alone
// doesn't settle it: a stone, end stone or petrified oak slab is still a slab
// and none of them are fuel. We may change this check later!
const wood_types = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'mangrove',
	'cherry', 'pale_oak', 'bamboo', 'crimson', 'warped']

// wooden_burn_ticks is how long any worked piece of wood keeps a furnace lit.
const wooden_burn_ticks = 300

// Fuel is how long an item keeps a furnace lit and what it leaves in the fuel
// slot afterwards.
pub struct Fuel {
pub:
	burn_ticks int
	// residue is the item that replaces the burnt one or empty when the fuel
	// is simply consumed.
	residue string
}

// fuel returns how an item burns or none when it doesn't burn at all.
pub fn fuel(name string) ?Fuel {
	if is_wooden(name) && (name.ends_with('_planks') || name.ends_with('_log')
		|| name.ends_with('_wood') || name.ends_with('_slab') || name.ends_with('_sapling')) {
		return Fuel{
			burn_ticks: wooden_burn_ticks
		}
	}
	if name == 'minecraft:lava_bucket' {
		return Fuel{
			burn_ticks: 20000
			residue:    'minecraft:bucket'
		}
	}
	burn := match name {
		'minecraft:coal_block' { 16000 }
		'minecraft:blaze_rod' { 2400 }
		'minecraft:coal', 'minecraft:charcoal' { 1600 }
		'minecraft:dried_kelp_block' { 4000 }
		'minecraft:stick' { 100 }
		else { return none }
	}
	return Fuel{
		burn_ticks: burn
	}
}

// is_wooden reports whether an identifier names something made of one of the
// tree materials.
fn is_wooden(name string) bool {
	base := name.trim_string_left('minecraft:').trim_string_left('stripped_')
	for wood in wood_types {
		if base.starts_with(wood + '_') {
			return true
		}
	}
	return false
}
