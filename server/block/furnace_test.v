module block

fn test_every_cooking_block_is_a_furnace() {
	assert furnace_variant('minecraft:furnace')? == .furnace
	assert furnace_variant('minecraft:blast_furnace')? == .blast_furnace
	assert furnace_variant('minecraft:smoker')? == .smoker
	// The burning form is the same block as far as behaviour goes.
	assert furnace_variant('minecraft:lit_furnace')? == .furnace
	assert furnace_variant('minecraft:lit_smoker')? == .smoker
	if _ := furnace_variant('minecraft:chest') {
		assert false, 'a chest reported itself as a furnace'
	}
}

fn test_the_specialised_blocks_cook_twice_as_fast() {
	assert FurnaceVariant.furnace.cook_ticks() == furnace_cook_ticks
	assert FurnaceVariant.blast_furnace.cook_ticks() == furnace_cook_ticks / 2
	assert FurnaceVariant.smoker.cook_ticks() == furnace_cook_ticks / 2
}

fn test_lighting_a_furnace_keeps_the_way_it_faces() {
	for direction in cardinal_directions {
		unlit := furnace_state_id('minecraft:furnace', direction)
		lit := furnace_state_id('minecraft:lit_furnace', direction)
		assert lit_furnace_id(unlit)? == lit
		assert unlit_furnace_id(lit)? == unlit
		assert is_lit_furnace(lit)
		assert !is_lit_furnace(unlit)
	}
}

fn test_a_block_that_is_not_a_furnace_has_no_lit_form() {
	if _ := lit_furnace_id(0) {
		assert false, 'block 0 reported a lit form'
	}
}
