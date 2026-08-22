module block

import server.world

// The state vocabulary several block families share, and the builders for the
// shapes that go with it. Keeping them here stops every family from spelling
// out the same palette state names.

const cardinal_directions = ['south', 'west', 'north', 'east']
const slab_halves = ['bottom', 'top']
const stair_corners = ['none', 'inner_left', 'inner_right', 'outer_left', 'outer_right']

fn cardinal_direction_state(direction string) world.BlockState {
	return world.BlockState{
		key:        'minecraft:cardinal_direction'
		kind:       world.state_kind_string
		string_val: direction
	}
}

// connection_states is the one bit per side that panes, bars and wires carry
// to say whether they join what is next to them.
fn connection_states(east u8, north u8, south u8, west u8) []world.BlockState {
	return [
		connection_state('east', east),
		connection_state('north', north),
		connection_state('south', south),
		connection_state('west', west),
	]
}

// all_connection_states is every combination of the four side bits, which is
// how a pane or a wire enumerates its palette states.
fn all_connection_states() [][]world.BlockState {
	mut out := [][]world.BlockState{cap: 16}
	for east in [u8(0), 1] {
		for north in [u8(0), 1] {
			for south in [u8(0), 1] {
				for west in [u8(0), 1] {
					out << connection_states(east, north, south, west)
				}
			}
		}
	}
	return out
}

fn connection_state(side string, connected u8) world.BlockState {
	return world.BlockState{
		key:        'minecraft:connection_${side}'
		kind:       world.state_kind_byte
		byte_value: connected
	}
}

fn slab_block(name string, half string, hardness f32) SimpleBlock {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'minecraft:vertical_half'
			kind:       world.state_kind_string
			string_val: half
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: hardness
	}
}

fn stairs_block(name string, corner string, upside_down u8, direction int, hardness f32) SimpleBlock {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'minecraft:corner'
			kind:       world.state_kind_string
			string_val: corner
		},
		world.BlockState{
			key:        'upside_down_bit'
			kind:       world.state_kind_byte
			byte_value: upside_down
		},
		world.BlockState{
			key:       'weirdo_direction'
			kind:      world.state_kind_int
			int_value: direction
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: hardness
	}
}
