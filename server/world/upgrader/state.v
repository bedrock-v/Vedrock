module upgrader

import server.world

pub const state_kind_byte = world.state_kind_byte
pub const state_kind_string = world.state_kind_string
pub const state_kind_int = world.state_kind_int

// StateValue is a single block property value. It keeps the kind so we can
// round-trip it back into the world.BlockState list without losing type info.
pub struct StateValue {
pub:
	kind       int
	byte_value u8
	string_val string
	int_value  int
}

pub fn byte_value(v u8) StateValue {
	return StateValue{
		kind:       state_kind_byte
		byte_value: v
	}
}

pub fn string_value(v string) StateValue {
	return StateValue{
		kind:       state_kind_string
		string_val: v
	}
}

pub fn int_value(v int) StateValue {
	return StateValue{
		kind:      state_kind_int
		int_value: v
	}
}

pub fn (v StateValue) == (other StateValue) bool {
	if v.kind != other.kind {
		return false
	}
	return match v.kind {
		state_kind_string { v.string_val == other.string_val }
		state_kind_int { v.int_value == other.int_value }
		else { v.byte_value == other.byte_value }
	}
}

// BlockState is the upgrader-facing model. It mirrors df-mc worldupgrader's
// BlockState{Name, Properties, Version}. Properties are keyed by name so
// schema transforms stay simple - order is irrelevant here since the final
// hash re-sorts states anyway.
pub struct BlockState {
pub mut:
	name       string
	properties map[string]StateValue
	version    int
}

// from_world turns the decoded name + sorted state list into a BlockState.
pub fn from_world(name string, states []world.BlockState, version int) BlockState {
	mut props := map[string]StateValue{}
	for s in states {
		props[s.key] = StateValue{
			kind:       s.kind
			byte_value: s.byte_value
			string_val: s.string_val
			int_value:  s.int_value
		}
	}
	return BlockState{
		name:       name
		properties: props
		version:    version
	}
}

// to_world flattens the BlockState back into a world.BlockState list ready
// for hashing. Keys are emitted sorted so the output is deterministic.
pub fn (b BlockState) to_world() []world.BlockState {
	mut keys := b.properties.keys()
	keys.sort()
	mut out := []world.BlockState{cap: keys.len}
	for key in keys {
		v := b.properties[key]
		out << world.BlockState{
			key:        key
			kind:       v.kind
			byte_value: v.byte_value
			string_val: v.string_val
			int_value:  v.int_value
		}
	}
	return out
}

// clone returns a deep copy so transforms never mutate the caller's map.
fn (b BlockState) clone() BlockState {
	mut props := map[string]StateValue{}
	for k, v in b.properties {
		props[k] = v
	}
	return BlockState{
		name:       b.name
		properties: props
		version:    b.version
	}
}
