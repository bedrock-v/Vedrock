module upgrader

// current_version is the block state version Vedrock treats as up to date.
// Anything stored below this gets walked through the schemas. The value is the
// packed Bedrock version used across the codebase (matches the palette dumps).
pub const current_version = 18163713

// Upgrader holds the ordered schema list and applies them to old block states.
// It is the single public entry point - construct once with default_upgrader()
// and call upgrade() per palette entry.
pub struct Upgrader {
mut:
	schemas []Schema
}

pub fn new_upgrader(schemas []Schema) Upgrader {
	mut sorted := schemas.clone()
	for i in 0 .. sorted.len {
		for j in i + 1 .. sorted.len {
			if sorted[j].id < sorted[i].id {
				sorted[i], sorted[j] = sorted[j], sorted[i]
			}
		}
	}
	return Upgrader{
		schemas: sorted
	}
}

// upgrade walks the schemas in id order, skipping any whose id the state has
// already passed. The block name and properties are rewritten in place and the
// version is bumped to current_version at the end. Already-current states are a
// pass-through no-op.
pub fn (u Upgrader) upgrade(state BlockState) BlockState {
	if state.version >= current_version {
		return state
	}
	mut out := state
	for schema in u.schemas {
		if out.version >= schema.id {
			continue
		}
		out = schema.apply(out)
		out.version = schema.id
	}
	out.version = current_version
	return out
}
