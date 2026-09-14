module block

fn test_chests_and_barrels_store_in_the_world() {
	for name in ['minecraft:chest', 'minecraft:trapped_chest', 'minecraft:barrel'] {
		kind := container_kind(name) or {
			assert false, '${name} is not a container'
			continue
		}
		assert kind.slots == container_default_slots
		assert !kind.player_scoped
	}
}

fn test_an_ender_chest_stores_on_the_player() {
	kind := container_kind('minecraft:ender_chest') or {
		assert false, 'ender chest is not a container'
		return
	}
	assert kind.player_scoped
	assert kind.slots == container_default_slots
}

fn test_every_shulker_box_colour_is_a_container() {
	for colour in shulker_colors {
		if _ := container_kind('minecraft:${colour}_shulker_box') {
		} else {
			assert false, '${colour} shulker box is not a container'
		}
	}
	if _ := container_kind('minecraft:undyed_shulker_box') {
	} else {
		assert false, 'undyed shulker box is not a container'
	}
}

fn test_a_block_that_stores_nothing_is_not_a_container() {
	if _ := container_kind('minecraft:stone') {
		assert false, 'stone reported itself as a container'
	}
	if _ := container_kind('minecraft:crafting_table') {
		assert false, 'a crafting table stores nothing'
	}
}
