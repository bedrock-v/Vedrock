module crafting

import protocol

// vanilla_recipes returns the built-in vanilla crafting recipes.
// This set grows as more blocks and items are modelled; it covers the
// essential wood-processing and basic tool chains.
pub fn vanilla_recipes() []Recipe {
	mut recs := []Recipe{}

	// -- planks from logs (2×2 player grid, shapeless) --------------------
	plank_woods := ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak',
		'mangrove', 'cherry', 'pale_oak', 'crimson', 'warped']
	for wood in plank_woods {
		recs << Recipe{
			id:           'minecraft:${wood}_planks'
			recipe_type:  protocol.recipe_shapeless
			input:        [RecipeInput{name: 'minecraft:${wood}_log', count: 1}]
			output_name:  'minecraft:${wood}_planks'
			output_count: 4
			priority:     0
		}
		recs << Recipe{
			id:           'minecraft:${wood}_planks_from_stripped_log'
			recipe_type:  protocol.recipe_shapeless
			input:        [RecipeInput{name: 'minecraft:stripped_${wood}_log', count: 1}]
			output_name:  'minecraft:${wood}_planks'
			output_count: 4
			priority:     0
		}
		recs << Recipe{
			id:           'minecraft:${wood}_planks_from_wood'
			recipe_type:  protocol.recipe_shapeless
			input:        [RecipeInput{name: 'minecraft:${wood}_wood', count: 1}]
			output_name:  'minecraft:${wood}_planks'
			output_count: 4
			priority:     0
		}
		recs << Recipe{
			id:           'minecraft:${wood}_planks_from_stripped_wood'
			recipe_type:  protocol.recipe_shapeless
			input:        [RecipeInput{name: 'minecraft:stripped_${wood}_wood', count: 1}]
			output_name:  'minecraft:${wood}_planks'
			output_count: 4
			priority:     0
		}
	}

	// -- sticks (2×2 player grid, shaped) ---------------------------------
	for wood in plank_woods {
		recs << Recipe{
			id:           'minecraft:stick_from_${wood}_planks'
			recipe_type:  protocol.recipe_shaped
			width:        1
			height:       2
			input: [
				RecipeInput{name: 'minecraft:${wood}_planks', count: 1},
				RecipeInput{name: 'minecraft:${wood}_planks', count: 1},
			]
			output_name:  'minecraft:stick'
			output_count: 4
			priority:     0
		}
	}
	// sticks from bamboo
	recs << Recipe{
		id:           'minecraft:stick_from_bamboo'
		recipe_type:  protocol.recipe_shapeless
		input:        [RecipeInput{name: 'minecraft:bamboo', count: 1}]
		output_name:  'minecraft:stick'
		output_count: 1
		priority:     0
	}

	// -- crafting table (2×2 player grid, shaped 2×2) --------------------
	recs << Recipe{
		id:          'minecraft:crafting_table'
		recipe_type: protocol.recipe_shaped
		width:       2
		height:      2
		input: [
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
		]
		output_name:  'minecraft:crafting_table'
		output_count: 1
		priority:     0
	}

	// -- chest (3×3, shaped, 8 planks ring) ------------------------------
	recs << Recipe{
		id:          'minecraft:chest'
		recipe_type: protocol.recipe_shaped
		width:       3
		height:      3
		block:       'minecraft:crafting_table'
		input: [
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
		]
		output_name:  'minecraft:chest'
		output_count: 1
		priority:     0
	}

	// -- sticks 2×2 (alternative pattern, high priority so recipe book
	//    shows this one) ---------------------------------------------------
	recs << Recipe{
		id:          'minecraft:sticks_2x2'
		recipe_type: protocol.recipe_shaped
		width:       2
		height:      2
		input: [
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
			RecipeInput{name: 'minecraft:oak_planks', count: 1},
		]
		output_name:  'minecraft:stick'
		output_count: 4
		priority:     5
	}

	// -- torches -----------------------------------------------------------
	recs << Recipe{
		id:          'minecraft:torch'
		recipe_type: protocol.recipe_shaped
		width:       1
		height:      2
		input: [
			RecipeInput{name: 'minecraft:coal', count: 1},
			RecipeInput{name: 'minecraft:stick', count: 1},
		]
		output_name:  'minecraft:torch'
		output_count: 4
		priority:     0
	}
	recs << Recipe{
		id:          'minecraft:torch_from_charcoal'
		recipe_type: protocol.recipe_shaped
		width:       1
		height:      2
		input: [
			RecipeInput{name: 'minecraft:charcoal', count: 1},
			RecipeInput{name: 'minecraft:stick', count: 1},
		]
		output_name:  'minecraft:torch'
		output_count: 4
		priority:     0
	}

	// -- furnace (3×3, shaped, 8 cobblestone ring) -------------------------
	recs << Recipe{
		id:          'minecraft:furnace'
		recipe_type: protocol.recipe_shaped
		width:       3
		height:      3
		block:       'minecraft:crafting_table'
		input: [
			RecipeInput{name: 'minecraft:cobblestone', count: 1},
			RecipeInput{name: 'minecraft:cobblestone', count: 1},
			RecipeInput{name: 'minecraft:cobblestone', count: 1},
			RecipeInput{name: 'minecraft:cobblestone', count: 1},
			RecipeInput{},
			RecipeInput{name: 'minecraft:cobblestone', count: 1},
			RecipeInput{name: 'minecraft:cobblestone', count: 1},
			RecipeInput{name: 'minecraft:cobblestone', count: 1},
			RecipeInput{name: 'minecraft:cobblestone', count: 1},
		]
		output_name:  'minecraft:furnace'
		output_count: 1
		priority:     0
	}

	// -- wooden tools (3×3, shaped) ---------------------------------------
	tool_materials := ['oak_planks', 'cobblestone', 'iron_ingot',
		'gold_ingot', 'diamond', 'netherite_ingot']
	tool_prefixes := ['wooden', 'stone', 'iron', 'golden', 'diamond', 'netherite']
	for i, material in tool_materials {
		prefix := tool_prefixes[i]
		stick := RecipeInput{name: 'minecraft:stick', count: 1}
		mat := RecipeInput{name: 'minecraft:${material}', count: 1}

		// pickaxe
		recs << Recipe{
			id:          'minecraft:${prefix}_pickaxe'
			recipe_type: protocol.recipe_shaped
			width:       3
			height:      3
			block:       'minecraft:crafting_table'
			input:       [mat, mat, mat, RecipeInput{}, stick, RecipeInput{}, RecipeInput{}, stick, RecipeInput{}]
			output_name: 'minecraft:${prefix}_pickaxe'
			output_count: 1
			priority:    0
		}
		// axe
		recs << Recipe{
			id:          'minecraft:${prefix}_axe'
			recipe_type: protocol.recipe_shaped
			width:       3
			height:      3
			block:       'minecraft:crafting_table'
			input:       [mat, mat, RecipeInput{}, mat, stick, RecipeInput{}, RecipeInput{}, stick, RecipeInput{}]
			output_name: 'minecraft:${prefix}_axe'
			output_count: 1
			priority:    0
		}
		// axe mirrored
		recs << Recipe{
			id:          'minecraft:${prefix}_axe_mirrored'
			recipe_type: protocol.recipe_shaped
			width:       3
			height:      3
			block:       'minecraft:crafting_table'
			input:       [RecipeInput{}, mat, mat, RecipeInput{}, stick, mat, RecipeInput{}, stick, RecipeInput{}]
			output_name: 'minecraft:${prefix}_axe'
			output_count: 1
			priority:    0
		}
		// sword
		recs << Recipe{
			id:          'minecraft:${prefix}_sword'
			recipe_type: protocol.recipe_shaped
			width:       3
			height:      3
			block:       'minecraft:crafting_table'
			input:       [RecipeInput{}, mat, RecipeInput{}, RecipeInput{}, mat, RecipeInput{}, RecipeInput{}, stick, RecipeInput{}]
			output_name: 'minecraft:${prefix}_sword'
			output_count: 1
			priority:    0
		}
		// shovel
		recs << Recipe{
			id:          'minecraft:${prefix}_shovel'
			recipe_type: protocol.recipe_shaped
			width:       3
			height:      3
			block:       'minecraft:crafting_table'
			input:       [RecipeInput{}, mat, RecipeInput{}, RecipeInput{}, stick, RecipeInput{}, RecipeInput{}, stick, RecipeInput{}]
			output_name: 'minecraft:${prefix}_shovel'
			output_count: 1
			priority:    0
		}
		// hoe
		recs << Recipe{
			id:          'minecraft:${prefix}_hoe'
			recipe_type: protocol.recipe_shaped
			width:       3
			height:      3
			block:       'minecraft:crafting_table'
			input:       [mat, mat, RecipeInput{}, RecipeInput{}, stick, RecipeInput{}, RecipeInput{}, stick, RecipeInput{}]
			output_name: 'minecraft:${prefix}_hoe'
			output_count: 1
			priority:    0
		}
		// hoe mirrored
		recs << Recipe{
			id:          'minecraft:${prefix}_hoe_mirrored'
			recipe_type: protocol.recipe_shaped
			width:       3
			height:      3
			block:       'minecraft:crafting_table'
			input:       [RecipeInput{}, mat, mat, RecipeInput{}, stick, RecipeInput{}, RecipeInput{}, stick, RecipeInput{}]
			output_name: 'minecraft:${prefix}_hoe'
			output_count: 1
			priority:    0
		}
	}

	return recs
}
