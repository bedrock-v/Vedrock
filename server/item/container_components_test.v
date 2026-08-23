module item

fn test_container_items_place_correct_block() {
	r := new_registry()
	chest := r.get('minecraft:chest') or { panic('missing chest item') }
	furnace := r.get('minecraft:furnace') or { panic('missing furnace item') }
	assert chest.block_runtime_id() != 0
	assert furnace.block_runtime_id() != 0
	assert chest.max_stack_size() == 64
}

fn test_lit_furnace_family_has_no_item() {
	r := new_registry()
	assert r.get('minecraft:lit_furnace') == none
	assert r.get('minecraft:lit_blast_furnace') == none
	assert r.get('minecraft:lit_smoker') == none
}

fn test_shulker_box_items_registered() {
	r := new_registry()
	undyed := r.get('minecraft:undyed_shulker_box') or { panic('missing undyed_shulker_box item') }
	blue := r.get('minecraft:blue_shulker_box') or { panic('missing blue_shulker_box item') }
	assert undyed.block_runtime_id() != blue.block_runtime_id()
}
