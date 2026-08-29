module item

// RecipeIngredient is one required input for a Recipe, aggregated by
// identity. Name + total count needed, grid position never checked.
pub struct RecipeIngredient {
pub:
	name  string
	count int
}

// Recipe is a crafting table recipe. Matching is identity & quantity only
// (ignores grid position). width/height/pattern exist only for CraftingDataPacket's
// wire encoding.
pub struct Recipe {
pub:
	id           string
	ingredients  []RecipeIngredient
	output_name  string
	output_count int
	block        string = 'crafting_table'
	width        int
	height       int
	pattern      []string
	// 0 is never a valid recipe_network_id on the wire.
	network_id u32
}

fn shapeless(id string, ingredients []RecipeIngredient, output_name string, output_count int) Recipe {
	return Recipe{
		id:           id
		ingredients:  ingredients
		output_name:  output_name
		output_count: output_count
	}
}

fn shaped(id string, width int, height int, pattern []string, output_name string, output_count int) Recipe {
	mut counts := map[string]int{}
	mut order := []string{}
	for cell in pattern {
		if cell == '' {
			continue
		}
		if cell !in counts {
			order << cell
		}
		counts[cell]++
	}
	mut ingredients := []RecipeIngredient{cap: order.len}
	for name in order {
		ingredients << RecipeIngredient{
			name:  name
			count: counts[name]
		}
	}
	return Recipe{
		id:           id
		ingredients:  ingredients
		output_name:  output_name
		output_count: output_count
		width:        width
		height:       height
		pattern:      pattern
	}
}

fn ing(name string, count int) RecipeIngredient {
	return RecipeIngredient{
		name:  name
		count: count
	}
}

const log_wood_types = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'mangrove',
	'cherry', 'pale_oak', 'poplar']

fn log_to_planks_recipes() []Recipe {
	mut out := []Recipe{cap: log_wood_types.len}
	for t in log_wood_types {
		out << shapeless('${t}_planks', [ing('minecraft:${t}_log', 1)], 'minecraft:${t}_planks', 4)
	}
	return out
}

fn tool_recipes(id_prefix string, material string, out_prefix string) []Recipe {
	return [
		shaped('${id_prefix}_pickaxe', 3, 3, [
			material,
			material,
			material,
			'',
			'minecraft:stick',
			'',
			'',
			'minecraft:stick',
			'',
		], 'minecraft:${out_prefix}_pickaxe', 1),
		shaped('${id_prefix}_axe', 2, 3, [
			material,
			material,
			material,
			'minecraft:stick',
			'',
			'minecraft:stick',
		], 'minecraft:${out_prefix}_axe', 1),
		shaped('${id_prefix}_shovel', 1, 3, [
			material,
			'minecraft:stick',
			'minecraft:stick',
		], 'minecraft:${out_prefix}_shovel', 1),
		shaped('${id_prefix}_hoe', 2, 3, [
			material,
			material,
			'',
			'minecraft:stick',
			'',
			'minecraft:stick',
		], 'minecraft:${out_prefix}_hoe', 1),
		shaped('${id_prefix}_sword', 1, 3, [
			material,
			material,
			'minecraft:stick',
		], 'minecraft:${out_prefix}_sword', 1),
	]
}

// default_recipes is a small, representative crafting table progression,
// not an exhaustive vanilla recipe book.
fn default_recipes() []Recipe {
	mut out := []Recipe{}
	out << log_to_planks_recipes()
	out << [
		shaped('stick', 1, 2, ['minecraft:oak_planks', 'minecraft:oak_planks'], 'minecraft:stick', 4),

		shaped('crafting_table', 2, 2, ['minecraft:oak_planks', 'minecraft:oak_planks',
			'minecraft:oak_planks', 'minecraft:oak_planks'], 'minecraft:crafting_table', 1),

		shaped('chest', 3, 3, ['minecraft:oak_planks', 'minecraft:oak_planks', 'minecraft:oak_planks',
			'minecraft:oak_planks', '', 'minecraft:oak_planks', 'minecraft:oak_planks',
			'minecraft:oak_planks', 'minecraft:oak_planks'], 'minecraft:chest', 1),

		shaped('furnace', 3, 3, ['minecraft:cobblestone', 'minecraft:cobblestone',
			'minecraft:cobblestone', 'minecraft:cobblestone', '', 'minecraft:cobblestone',
			'minecraft:cobblestone', 'minecraft:cobblestone', 'minecraft:cobblestone'],
			'minecraft:furnace', 1),

		shaped('torch', 1, 2, ['minecraft:coal', 'minecraft:stick'], 'minecraft:torch', 4),

		shaped('jukebox', 3, 3, ['minecraft:oak_planks', 'minecraft:oak_planks',
			'minecraft:oak_planks', 'minecraft:oak_planks', 'minecraft:diamond',
			'minecraft:oak_planks', 'minecraft:oak_planks', 'minecraft:oak_planks',
			'minecraft:oak_planks'], 'minecraft:jukebox', 1),

		shaped('bucket', 3, 2, ['minecraft:iron_ingot', '', 'minecraft:iron_ingot', '',
			'minecraft:iron_ingot', ''], 'minecraft:bucket', 1),

		shaped('bread', 3, 1, ['minecraft:wheat', 'minecraft:wheat', 'minecraft:wheat'],
			'minecraft:bread', 1),
	]

	out << tool_recipes('wooden', 'minecraft:oak_planks', 'wooden')

	out << tool_recipes('stone', 'minecraft:cobblestone', 'stone')

	out << tool_recipes('iron', 'minecraft:iron_ingot', 'iron')

	out << tool_recipes('diamond', 'minecraft:diamond', 'diamond')

	return out
}

pub struct RecipeRegistry {
mut:
	recipes    []Recipe
	by_network map[u32]int
}

fn (mut reg RecipeRegistry) register(r Recipe) {
	with_id := Recipe{
		...r
		network_id: u32(reg.recipes.len + 1)
	}
	reg.recipes << with_id
	reg.by_network[with_id.network_id] = reg.recipes.len - 1
}

pub fn (r &RecipeRegistry) by_network_id(id u32) ?Recipe {
	idx := r.by_network[id] or { return none }
	return r.recipes[idx]
}

pub fn (r &RecipeRegistry) all() []Recipe {
	return r.recipes
}

const process_recipes = &RecipeRegistry{}

// init_recipes seeds process_recipes. Called from registry.v's init(),
// since V rejects a second init() in the same module.
fn init_recipes() {
	mut r := process_recipes
	for rec in default_recipes() {
		r.register(rec)
	}
}

pub fn recipe_by_network_id(id u32) ?Recipe {
	return process_recipes.by_network_id(id)
}

pub fn all_recipes() []Recipe {
	return process_recipes.all()
}
