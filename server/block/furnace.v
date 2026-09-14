module block

import server.world

// FurnaceVariant is which of the three cooking blocks a furnace is. They
// differ only in how fast they cook and in what they will accept, which the
// session decides from here rather than from the block name.
pub enum FurnaceVariant {
	furnace
	blast_furnace
	smoker
}

// furnace_cook_ticks is how long this variant takes to cook one item.
pub fn (v FurnaceVariant) cook_ticks() int {
	return if v == .furnace { furnace_cook_ticks } else { furnace_cook_ticks / 2 }
}

pub const furnace_cook_ticks = 200

// furnace_slot_input, _fuel and _output are the three slots a furnace shows,
// in the order the client addresses them.
pub const furnace_slot_input = 0
pub const furnace_slot_fuel = 1
pub const furnace_slot_output = 2
pub const furnace_slot_count = 3

const furnace_names = {
	'minecraft:furnace':       FurnaceVariant.furnace
	'minecraft:blast_furnace': FurnaceVariant.blast_furnace
	'minecraft:smoker':        FurnaceVariant.smoker
}

// furnace_variant returns which cooking block an identifier names, lit or not.
pub fn furnace_variant(identifier string) ?FurnaceVariant {
	name := identifier.replace('minecraft:lit_', 'minecraft:')
	return furnace_names[name] or { return none }
}

// furnace_lit_ids and furnace_unlit_ids map a furnace between its two block
// states without the caller having to know which way it faces. They are built
// once from the same names and directions the container blocks are registered
// with, so the two can never drift apart.
pub const furnace_lit_ids = build_furnace_ids(false)
pub const furnace_unlit_ids = build_furnace_ids(true)

fn build_furnace_ids(from_lit bool) map[int]int {
	mut out := map[int]int{}
	for name, _ in furnace_names {
		lit_name := name.replace('minecraft:', 'minecraft:lit_')
		for direction in cardinal_directions {
			unlit := furnace_state_id(name, direction)
			lit := furnace_state_id(lit_name, direction)
			if from_lit {
				out[lit] = unlit
			} else {
				out[unlit] = lit
			}
		}
	}
	return out
}

fn furnace_state_id(name string, direction string) int {
	return world.new_block_with_states(name, [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: direction
		},
	]).network_id
}

// lit_furnace_id is the burning form of a furnace block, keeping the way it
// faces. It returns none for anything that is not an unlit furnace.
pub fn lit_furnace_id(block_id int) ?int {
	return furnace_lit_ids[block_id] or { return none }
}

// unlit_furnace_id is the reverse.
pub fn unlit_furnace_id(block_id int) ?int {
	return furnace_unlit_ids[block_id] or { return none }
}

// is_lit_furnace reports whether a furnace block is currently burning.
pub fn is_lit_furnace(block_id int) bool {
	return block_id in furnace_unlit_ids
}
