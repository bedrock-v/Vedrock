module block

import server.world

// Every hand registered block is addressed by the hash of its name and states,
// so a misspelled state, a byte written where the palette holds an int, or a
// value the palette never carries all produce an id no client will ever send.
// The palette is the only thing that can tell the difference.
fn test_registered_runtime_ids_name_the_block_they_belong_to() {
	palette := world.load_palette('../../data/block_palette.nbt') or {
		world.load_palette('data/block_palette.nbt') or { panic('cannot load palette: ${err}') }
	}
	r := new_registry()
	for runtime_id, b in r.by_runtime {
		variant := palette.variant(runtime_id) or {
			assert false, '${b.identifier()} has no palette state for id ${runtime_id}'
			continue
		}
		assert variant.name == b.identifier()
	}
}
