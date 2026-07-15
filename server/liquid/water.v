module liquid

import server.world

// Water depth model, adapted from dragonfly and PocketMine.
//
// depth runs 1..8 internally: 8 is a source, 1..7 are flowing levels where a
// higher number is a fuller (taller) cell, and a falling cell behaves like a
// full column. Each horizontal step loses spread_decay levels, so a source
// reaches at most 7 cells away before the flow is exhausted.
//
// Bedrock encodes this in the liquid_depth block state as liquid_depth = 8 -
// depth, with +8 added when the cell is falling. A source is minecraft:water
// (still); anything flowing is minecraft:flowing_water.
pub const source_depth = 8
pub const max_flow_depth = 7
pub const spread_decay = 1
pub const min_adjacent_sources = 2

// WaterState is a resolved water cell: its internal depth and whether it is
// falling. It knows how to encode itself into a Bedrock network id.
pub struct WaterState {
pub:
	depth   int
	falling bool
}

// is_source reports whether this cell is a full still source.
pub fn (w WaterState) is_source() bool {
	return w.depth == source_depth && !w.falling
}

// liquid_depth_value returns the Bedrock liquid_depth state value for this cell.
fn (w WaterState) liquid_depth_value() int {
	mut v := source_depth - w.depth
	if w.falling {
		v += 8
	}
	return v
}

// network_id resolves this water cell to its Bedrock runtime id. Source cells
// use minecraft:water, flowing/falling cells use minecraft:flowing_water.
pub fn (w WaterState) network_id() int {
	name := if w.is_source() { 'minecraft:water' } else { 'minecraft:flowing_water' }
	return world.new_block_with_states(name, [
		world.BlockState{
			key:       'liquid_depth'
			kind:      world.state_kind_int
			int_value: w.liquid_depth_value()
		},
	]).network_id
}

// new_source is the full still water source.
pub fn new_source() WaterState {
	return WaterState{
		depth:   source_depth
		falling: false
	}
}

// new_flowing builds a flowing cell at the given depth.
pub fn new_flowing(depth int) WaterState {
	return WaterState{
		depth:   depth
		falling: false
	}
}

// new_falling is a falling column - it appears full but spreads like flowing.
pub fn new_falling() WaterState {
	return WaterState{
		depth:   source_depth
		falling: true
	}
}
