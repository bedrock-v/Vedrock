module db

import server.block
import server.world

struct TestCropBlock {
	block.SimpleBlock
	hits &int
}

fn (b TestCropBlock) random_tick(x int, y int, z int, mut w block.TickWorld) {
	p := b.hits
	unsafe {
		*p = *p + 1
	}
}

struct TestWaterBlock {
	block.SimpleBlock
	hits &int
}

fn (b TestWaterBlock) scheduled_tick(x int, y int, z int, mut w block.TickWorld) {
	p := b.hits
	unsafe {
		*p = *p + 1
	}
	w.set_block(x, y, z, world.air.network_id)
}

fn test_scheduled_tick_fires_exactly_once_after_delay() {
	mut registry := block.new_registry()
	mut hits := 0
	water := TestWaterBlock{
		SimpleBlock: block.SimpleBlock{
			id:            'test:water'
			block_runtime: 555001
		}
		hits:        &hits
	}
	registry.register(water)

	mut w := new_world('test', unsafe { nil }, 'void', world.overworld)
	w.set_block(1, 2, 3, 555001)
	w.schedule_tick(1, 2, 3, 2)

	w.tick(&registry) // tick 1: due=2, not yet
	assert hits == 0
	changed := w.tick(&registry) // tick 2: due
	assert hits == 1
	assert changed.len == 1
	assert changed[0].id == world.air.network_id

	_ = w.tick(&registry) // tick 3: must not fire again
	assert hits == 1
}

fn test_random_tick_eventually_fires_for_overridden_block() {
	mut registry := block.new_registry()
	mut hits := 0
	crop := TestCropBlock{
		SimpleBlock: block.SimpleBlock{
			id:            'test:crop'
			block_runtime: 555002
		}
		hits:        &hits
	}
	registry.register(crop)

	mut w := new_world('test', unsafe { nil }, 'void', world.overworld)
	w.set_block(5, 5, 5, 555002)

	// The expected number of hits over 50000 ticks is about 36.
	// The probability of receiving no hits is negligibly small, so this test shouldn't be realistically flaky.
	for _ in 0 .. 50000 {
		w.tick(&registry)
	}
	assert hits > 0
}

struct TestSwappingCropBlock {
	block.SimpleBlock
	old_hits &int
	new_id   int
}

fn (b TestSwappingCropBlock) random_tick(x int, y int, z int, mut w block.TickWorld) {
	p := b.old_hits
	unsafe {
		*p = *p + 1
	}
}

fn (b TestSwappingCropBlock) scheduled_tick(x int, y int, z int, mut w block.TickWorld) {
	w.set_block(x, y, z, b.new_id)
}

struct TestNewCropBlock {
	block.SimpleBlock
	new_hits &int
}

fn (b TestNewCropBlock) random_tick(x int, y int, z int, mut w block.TickWorld) {
	p := b.new_hits
	unsafe {
		*p = *p + 1
	}
}

fn test_random_tick_uses_block_left_by_same_tick_scheduled_tick() {
	mut registry := block.new_registry()
	mut old_hits := 0
	mut new_hits := 0
	old_block := TestSwappingCropBlock{
		SimpleBlock: block.SimpleBlock{
			id:            'test:swapping_crop'
			block_runtime: 555010
		}
		old_hits:    &old_hits
		new_id:      555011
	}
	new_block := TestNewCropBlock{
		SimpleBlock: block.SimpleBlock{
			id:            'test:new_crop'
			block_runtime: 555011
		}
		new_hits:    &new_hits
	}
	registry.register(old_block)
	registry.register(new_block)

	mut w := new_world('test', unsafe { nil }, 'void', world.overworld)
	for _ in 0 .. 50000 {
		w.set_block(7, 7, 7, 555010)
		w.schedule_tick(7, 7, 7, 0)
		w.tick(&registry)
	}

	assert old_hits == 0
	assert new_hits > 0
}

struct TestNoopBlock {
	block.SimpleBlock
	hits &int
}

fn (b TestNoopBlock) scheduled_tick(x int, y int, z int, mut w block.TickWorld) {
	p := b.hits
	unsafe {
		*p = *p + 1
	}
}

fn test_scheduled_tick_without_a_block_change_is_not_reported() {
	mut registry := block.new_registry()
	mut hits := 0
	noop := TestNoopBlock{
		SimpleBlock: block.SimpleBlock{
			id:            'test:noop'
			block_runtime: 555020
		}
		hits:        &hits
	}
	registry.register(noop)

	mut w := new_world('test', unsafe { nil }, 'void', world.overworld)
	w.set_block(9, 9, 9, 555020)
	w.schedule_tick(9, 9, 9, 1)

	changed := w.tick(&registry)
	assert hits == 1
	assert changed.len == 0
}

fn test_block_id_falls_back_to_generator_without_override() {
	mut w := new_world('test', unsafe { nil }, 'flat', world.overworld)
	// Flat's bottom layer is bedrock (see server/world/generator.v's
	// FlatGenerator.layers()), not stone - this just needs any known solid
	// block from the generator to prove the override-fallback path.
	assert w.block_id(0, -64, 0) == world.bedrock.network_id
	assert w.block_id(0, 10, 0) == world.air.network_id

	w.set_block(0, -64, 0, world.dirt.network_id)
	assert w.block_id(0, -64, 0) == world.dirt.network_id
}

fn test_tick_ignores_overridden_blocks_without_ticker_behaviour() {
	registry := block.new_registry()
	mut w := new_world('test', unsafe { nil }, 'void', world.overworld)
	w.set_block(0, 0, 0, world.stone.network_id)
	changed := w.tick(&registry)
	assert changed.len == 0
}
