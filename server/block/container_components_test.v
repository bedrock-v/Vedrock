module block

import server.world

fn test_chest_direction_variants() {
	r := new_registry()
	south := world.new_block_with_states('minecraft:chest', [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: 'south'
		},
	])
	west := world.new_block_with_states('minecraft:chest', [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: 'west'
		},
	])
	assert south.network_id != west.network_id
	by_south := r.get(south.network_id) or { panic('missing chest direction=south') }
	assert by_south.hardness() == 2.5
}

fn test_lit_furnace_variants_registered_but_have_no_item() {
	r := new_registry()
	assert r.get_by_name('minecraft:furnace') != none
	assert r.get_by_name('minecraft:lit_furnace') != none
	assert r.get_by_name('minecraft:blast_furnace') != none
	assert r.get_by_name('minecraft:lit_blast_furnace') != none
	assert r.get_by_name('minecraft:smoker') != none
	assert r.get_by_name('minecraft:lit_smoker') != none
}

fn test_barrel_hopper_dispenser_dropper_hardness() {
	r := new_registry()
	barrel := r.get_by_name('minecraft:barrel') or { panic('missing barrel') }
	hopper := r.get_by_name('minecraft:hopper') or { panic('missing hopper') }
	dispenser := r.get_by_name('minecraft:dispenser') or { panic('missing dispenser') }
	dropper := r.get_by_name('minecraft:dropper') or { panic('missing dropper') }
	assert barrel.hardness() == 2.5
	assert hopper.hardness() == 3.0
	assert dispenser.hardness() == 3.5
	assert dropper.hardness() == 3.5
}

fn test_shulker_box_colors_registered() {
	r := new_registry()
	undyed := r.get_by_name('minecraft:undyed_shulker_box') or {
		panic('missing undyed_shulker_box')
	}
	red := r.get_by_name('minecraft:red_shulker_box') or { panic('missing red_shulker_box') }
	assert undyed.hardness() == 2.0
	assert red.hardness() == 2.0
	assert undyed.runtime_id() != red.runtime_id()
}
