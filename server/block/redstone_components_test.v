module block

import server.world

fn test_redstone_wire_signal_variants() {
	r := new_registry()
	lit := world.new_block_with_states('minecraft:redstone_wire', [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 15
		},
	])
	unlit := world.new_block_with_states('minecraft:redstone_wire', [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	assert lit.network_id != unlit.network_id
	by_lit := r.get(lit.network_id) or { panic('missing redstone_wire signal=15') }
	assert by_lit.hardness() == 0.0
	assert by_lit.breakable()
}

fn test_repeater_item_id_differs_from_block_id() {
	r := new_registry()
	assert r.get_by_name('minecraft:unpowered_repeater') != none
	assert r.get_by_name('minecraft:powered_repeater') != none
	assert r.get_by_name('minecraft:repeater') == none
}

fn test_button_family_registered() {
	r := new_registry()
	wooden := r.get_by_name('minecraft:wooden_button') or { panic('missing wooden_button') }
	stone := r.get_by_name('minecraft:stone_button') or { panic('missing stone_button') }
	blackstone := r.get_by_name('minecraft:polished_blackstone_button') or {
		panic('missing polished_blackstone_button')
	}
	assert wooden.hardness() == 0.5
	assert stone.hardness() == 0.5
	assert blackstone.hardness() == 0.5
}

fn test_pressure_plate_family_registered() {
	r := new_registry()
	assert r.get_by_name('minecraft:light_weighted_pressure_plate') != none
	assert r.get_by_name('minecraft:heavy_weighted_pressure_plate') != none
	assert r.get_by_name('minecraft:stone_pressure_plate') != none
}

fn test_observer_and_piston_hardness() {
	r := new_registry()
	observer := r.get_by_name('minecraft:observer') or { panic('missing observer') }
	piston := r.get_by_name('minecraft:piston') or { panic('missing piston') }
	sticky := r.get_by_name('minecraft:sticky_piston') or { panic('missing sticky_piston') }
	assert observer.hardness() == 3.0
	assert piston.hardness() == 1.5
	assert sticky.hardness() == 1.5
}

fn test_lamp_daylight_and_tripwire_registered() {
	r := new_registry()
	assert r.get_by_name('minecraft:redstone_lamp') != none
	assert r.get_by_name('minecraft:lit_redstone_lamp') != none
	assert r.get_by_name('minecraft:daylight_detector') != none
	assert r.get_by_name('minecraft:daylight_detector_inverted') != none
	assert r.get_by_name('minecraft:tripwire_hook') != none
	assert r.get_by_name('minecraft:trip_wire') != none
}

// FakeTickWorld is a minimal in memory TickWorld fixture for testing
// Interactable/RandomTicker/ScheduledTicker blocks without a real db.World.
struct FakeTickWorld {
mut:
	blocks map[string]int
}

fn (w &FakeTickWorld) block_id(x int, y int, z int) int {
	return w.blocks['${x}:${y}:${z}'] or { 0 }
}

fn (mut w FakeTickWorld) set_block(x int, y int, z int, id int) {
	w.blocks['${x}:${y}:${z}'] = id
}

fn (mut w FakeTickWorld) schedule_tick(x int, y int, z int, delay int) {}

fn test_repeater_is_interactable_and_cycles_delay_back_to_start() {
	r := new_registry()
	base := r.get_by_name('minecraft:unpowered_repeater') or { panic('missing unpowered_repeater') }
	assert base is RepeaterBlock
	assert base is Interactable

	mut w := FakeTickWorld{}
	start_id := base.runtime_id()
	mut current_id := start_id
	mut ids := []int{}
	for _ in 0 .. 4 {
		cur := r.get(current_id) or { panic('missing repeater variant') }
		if cur is RepeaterBlock {
			cur.interact(0, 0, 0, 1, mut w)
		}
		current_id = w.block_id(0, 0, 0)
		ids << current_id
	}
	assert ids[3] == start_id
	assert ids[0] != ids[1]
	assert ids[1] != ids[2]
	assert ids[2] != ids[3]
}

// TestPunchableBlock is a test only fixture proving Punchable's dispatch
// shape works.
struct TestPunchableBlock {
	SimpleBlock
}

fn (b TestPunchableBlock) punch(x int, y int, z int, click_face int, mut w TickWorld) {
	w.set_block(x, y, z, 999)
}

fn test_punchable_dispatches_to_the_block() {
	b := Block(TestPunchableBlock{})
	assert b is Punchable
	mut w := FakeTickWorld{}
	if b is Punchable {
		b.punch(0, 0, 0, 1, mut w)
	}
	assert w.block_id(0, 0, 0) == 999
}
