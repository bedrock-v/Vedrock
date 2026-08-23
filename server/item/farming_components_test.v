module item

fn test_carrot_and_potato_place_their_own_crop() {
	r := new_registry()
	carrot := r.get('minecraft:carrot') or { panic('missing carrot') }
	potato := r.get('minecraft:potato') or { panic('missing potato') }
	assert carrot.block_runtime_id() != 0
	assert potato.block_runtime_id() != 0
	assert carrot.nutrition() == 3
	assert potato.nutrition() == 1
}

fn test_wheat_and_beetroot_seeds_place_crop_blocks() {
	r := new_registry()
	wheat_seeds := r.get('minecraft:wheat_seeds') or { panic('missing wheat_seeds') }
	beetroot_seeds := r.get('minecraft:beetroot_seeds') or { panic('missing beetroot_seeds') }
	assert wheat_seeds.block_runtime_id() != 0
	assert beetroot_seeds.block_runtime_id() != 0
}

fn test_raw_wheat_is_not_food() {
	r := new_registry()
	wheat := r.get('minecraft:wheat') or { panic('missing wheat') }
	assert wheat.nutrition() == 0
	assert wheat is WheatItem
}

fn test_composter_and_bone_meal_registered() {
	r := new_registry()
	composter := r.get('minecraft:composter') or { panic('missing composter') }
	assert composter.block_runtime_id() != 0
	bone_meal := r.get('minecraft:bone_meal') or { panic('missing bone_meal') }
	assert bone_meal.max_stack_size() == 64
}

fn test_remaining_food_items_registered() {
	r := new_registry()
	cookie := r.get('minecraft:cookie') or { panic('missing cookie') }
	golden_carrot := r.get('minecraft:golden_carrot') or { panic('missing golden_carrot') }
	poisonous_potato := r.get('minecraft:poisonous_potato') or { panic('missing poisonous_potato') }
	assert cookie.nutrition() == 2
	assert golden_carrot.nutrition() == 6
	assert golden_carrot.saturation() == 14.4
	assert poisonous_potato.nutrition() == 2
}

fn test_farmland_has_no_item() {
	r := new_registry()
	assert r.get('minecraft:farmland') == none
}
