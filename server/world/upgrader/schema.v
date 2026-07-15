module upgrader

// StateRemap replaces a whole block state when the old properties match. It
// mirrors df-mc's schemaBlockRemap - if old_properties is a subset of the
// current state, the block is rewritten with new_name and new_properties,
// keeping any copied_properties from the old state.
pub struct StateRemap {
pub:
	old_properties    map[string]StateValue
	new_name          string
	new_properties    map[string]StateValue
	copied_properties []string
}

pub struct ValueRemap {
pub:
	old StateValue
	new StateValue
}

// Schema is one ordered upgrade step. Each map is keyed by block name. Only
// the transforms that a given step needs are filled in - the rest stay empty
// and are skipped. This matches worldupgrader's schema shape.
pub struct Schema {
pub:
	id                 int
	renamed_ids        map[string]string
	added_properties   map[string]map[string]StateValue
	removed_properties map[string][]string
	renamed_properties map[string]map[string]string
	remapped_values    map[string]map[string][]ValueRemap
	remapped_states    map[string][]StateRemap
}

// apply runs every transform in this schema against the state and returns the
// result. Order matches worldupgrader: state remaps first, then rename, then
// property add/remove/rename, then value remaps.
fn (s Schema) apply(state BlockState) BlockState {
	mut out := state.clone()
	out = s.apply_state_remaps(out)
	out = s.apply_rename(out)
	out = s.apply_added(out)
	out = s.apply_removed(out)
	out = s.apply_renamed_properties(out)
	out = s.apply_value_remaps(out)
	return out
}

fn (s Schema) apply_state_remaps(state BlockState) BlockState {
	remaps := s.remapped_states[state.name] or { return state }
	mut out := state
	for remap in remaps {
		if !properties_match(out.properties, remap.old_properties) {
			continue
		}
		mut props := map[string]StateValue{}
		for k, v in remap.new_properties {
			props[k] = v
		}
		for key in remap.copied_properties {
			if v := out.properties[key] {
				props[key] = v
			}
		}
		name := if remap.new_name != '' { remap.new_name } else { out.name }
		return BlockState{
			name:       name
			properties: props
			version:    out.version
		}
	}
	return out
}

fn (s Schema) apply_rename(state BlockState) BlockState {
	new_name := s.renamed_ids[state.name] or { return state }
	mut out := state
	out.name = new_name
	return out
}

fn (s Schema) apply_added(state BlockState) BlockState {
	if state.name !in s.added_properties {
		return state
	}
	mut out := state
	for key, value in s.added_properties[state.name] {
		if key !in out.properties {
			out.properties[key] = value
		}
	}
	return out
}

fn (s Schema) apply_removed(state BlockState) BlockState {
	removed := s.removed_properties[state.name] or { return state }
	mut out := state
	for key in removed {
		out.properties.delete(key)
	}
	return out
}

fn (s Schema) apply_renamed_properties(state BlockState) BlockState {
	if state.name !in s.renamed_properties {
		return state
	}
	mut out := state
	for old_key, new_key in s.renamed_properties[state.name] {
		if v := out.properties[old_key] {
			out.properties.delete(old_key)
			out.properties[new_key] = v
		}
	}
	return out
}

fn (s Schema) apply_value_remaps(state BlockState) BlockState {
	if state.name !in s.remapped_values {
		return state
	}
	mut out := state
	for key, remaps in s.remapped_values[state.name] {
		current := out.properties[key] or { continue }
		for remap in remaps {
			if current == remap.old {
				out.properties[key] = remap.new
				break
			}
		}
	}
	return out
}

// properties_match reports whether every entry in want is present in have with
// the same value. An empty want matches anything.
fn properties_match(have map[string]StateValue, want map[string]StateValue) bool {
	for key, value in want {
		got := have[key] or { return false }
		if got != value {
			return false
		}
	}
	return true
}
