module block

import server.world

// depth runs 1..8 internally: 8 is a source, 1..7 are flowing levels where a
// higher number is a fuller (taller) cell, and a falling cell behaves like a
// full column. Each horizontal step loses the liquid's spread decay, so water
// reaches at most 7 cells from its source and overworld lava only 3.
//
// Bedrock encodes this in the liquid_depth block state as liquid_depth = 8 -
// depth, with +8 added when the cell is falling. A source is minecraft:water
// or minecraft:lava (still); anything flowing is the flowing_ form.
pub const source_depth = 8
pub const max_flow_depth = 7
pub const spread_decay = 1
pub const lava_spread_decay = 2
pub const min_adjacent_sources = 2

// LiquidKind is which fluid a cell holds. The two behave the same way apart
// from how far they reach, how fast they move and what they do to each other.
pub enum LiquidKind {
	water
	lava
}

// LiquidState is a resolved liquid cell: which fluid, its internal depth and
// whether it is falling. It knows how to encode itself into a Bedrock network
// id.
pub struct LiquidState {
pub:
	kind    LiquidKind
	depth   int
	falling bool
}

// is_source reports whether this cell is a full still source.
pub fn (l LiquidState) is_source() bool {
	return l.depth == source_depth && !l.falling
}

// spread_decay is how much depth this liquid loses per horizontal step.
pub fn (l LiquidState) spread_decay() int {
	return if l.kind == .lava { lava_spread_decay } else { spread_decay }
}

// liquid_depth_value returns the Bedrock liquid_depth state value for this cell.
fn (l LiquidState) liquid_depth_value() int {
	mut v := source_depth - l.depth
	if l.falling {
		v += 8
	}
	return v
}

fn (l LiquidState) block_name() string {
	return match l.kind {
		.water {
			if l.is_source() {
				'minecraft:water'
			} else {
				'minecraft:flowing_water'
			}
		}
		.lava {
			if l.is_source() {
				'minecraft:lava'
			} else {
				'minecraft:flowing_lava'
			}
		}
	}
}

// network_id resolves this liquid cell to its Bedrock runtime id.
pub fn (l LiquidState) network_id() int {
	return world.new_block_with_states(l.block_name(), [
		world.BlockState{
			key:       'liquid_depth'
			kind:      world.state_kind_int
			int_value: l.liquid_depth_value()
		},
	]).network_id
}

// new_source is the full still water source.
pub fn new_source() LiquidState {
	return new_liquid_source(.water)
}

// new_flowing builds a flowing water cell at the given depth.
pub fn new_flowing(depth int) LiquidState {
	return new_liquid_flowing(.water, depth)
}

// new_falling is a falling water column - it appears full but spreads like
// flowing.
pub fn new_falling() LiquidState {
	return new_liquid_falling(.water)
}

pub fn new_liquid_source(kind LiquidKind) LiquidState {
	return LiquidState{
		kind:    kind
		depth:   source_depth
		falling: false
	}
}

pub fn new_liquid_flowing(kind LiquidKind, depth int) LiquidState {
	return LiquidState{
		kind:    kind
		depth:   depth
		falling: false
	}
}

pub fn new_liquid_falling(kind LiquidKind) LiquidState {
	return LiquidState{
		kind:    kind
		depth:   source_depth
		falling: true
	}
}

// liquid_states maps every liquid network id to the cell it stands for. It is
// built once so both the spread engine and the gameplay code that only wants
// to ask "is this lava?" read the same table.
pub const liquid_states = build_liquid_states()

fn build_liquid_states() map[int]LiquidState {
	mut states := map[int]LiquidState{}
	for kind in [LiquidKind.water, .lava] {
		source := new_liquid_source(kind)
		states[source.network_id()] = source
		falling := new_liquid_falling(kind)
		states[falling.network_id()] = falling
		for depth := 1; depth <= max_flow_depth; depth++ {
			flowing := new_liquid_flowing(kind, depth)
			states[flowing.network_id()] = flowing
		}
	}
	return states
}

// liquid_at_id returns the liquid cell a network id stands for, or none when
// the id is not a liquid at all.
pub fn liquid_at_id(id int) ?LiquidState {
	return liquid_states[id] or { return none }
}

// is_lava_id and is_water_id answer what a block id is without the caller
// having to know how many states each fluid has.
pub fn is_lava_id(id int) bool {
	state := liquid_at_id(id) or { return false }
	return state.kind == .lava
}

pub fn is_water_id(id int) bool {
	state := liquid_at_id(id) or { return false }
	return state.kind == .water
}
