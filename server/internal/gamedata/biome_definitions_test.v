module gamedata

import os
import nbt
import protocol.serializer

// PayloadWalker reads a BiomeDefinitionListPacket payload the way the client
// does. It proves the encoder lays every field out in the right order and
// width: a field written wrong desynchronises the walk and leaves the payload
// either short or with trailing bytes.
struct PayloadWalker {
	data []u8
mut:
	offset         int
	expression_ops []int
}

fn (mut r PayloadWalker) u8() !u8 {
	if r.offset >= r.data.len {
		return error('read past end at ${r.offset}')
	}
	value := r.data[r.offset]
	r.offset++
	return value
}

fn (mut r PayloadWalker) skip(count int) ! {
	if r.offset + count > r.data.len {
		return error('read past end at ${r.offset}')
	}
	r.offset += count
}

fn (mut r PayloadWalker) varuint() !int {
	mut shift := u32(0)
	mut value := u32(0)
	for {
		b := r.u8()!
		value |= u32(b & 0x7f) << shift
		if b < 0x80 {
			break
		}
		shift += 7
	}
	return int(value)
}

fn (mut r PayloadWalker) varint() !int {
	value := u32(r.varuint()!)
	return int((value >> 1) ^ (-(value & 1)))
}

fn (mut r PayloadWalker) boolean() !bool {
	return r.u8()! != 0
}

fn (mut r PayloadWalker) text() ! {
	length := r.varuint()!
	r.skip(length)!
}

fn (mut r PayloadWalker) list(entry fn (mut PayloadWalker) !) ! {
	count := r.varuint()!
	for _ in 0 .. count {
		entry(mut r)!
	}
}

fn (mut r PayloadWalker) optional(entry fn (mut PayloadWalker) !) ! {
	if r.boolean()! {
		entry(mut r)!
	}
}

// expression_op records every molang type it walks past, so a test can assert
// the absent ones went out as the "no expression" marker.
fn (mut r PayloadWalker) expression_op() ! {
	value := r.varint()!
	r.expression_ops << value
}

fn (mut r PayloadWalker) coordinate() ! {
	r.expression_op()!
	r.skip(2)!
	r.expression_op()!
	r.skip(2 + 4 + 4)!
	r.varint()!
}

fn (mut r PayloadWalker) scatter() ! {
	r.list(fn (mut w PayloadWalker) ! {
		w.coordinate()!
	})!
	r.varint()!
	r.expression_op()!
	r.skip(2 + 4 + 4)!
	r.expression_op()!
	r.skip(2)!
}

fn (mut r PayloadWalker) feature() ! {
	r.scatter()!
	r.skip(2 + 2 + 2 + 1)!
}

fn (mut r PayloadWalker) surface_material() ! {
	r.skip(6 * 4)!
}

fn (mut r PayloadWalker) element() ! {
	r.skip(3 * 4)!
	r.expression_op()!
	r.skip(2)!
	r.expression_op()!
	r.skip(2)!
	r.surface_material()!
}

fn (mut r PayloadWalker) weighted() ! {
	r.skip(2 + 4)!
}

fn (mut r PayloadWalker) conditional() ! {
	r.list(fn (mut w PayloadWalker) ! {
		w.weighted()!
	})!
	r.skip(2 + 4)!
}

fn (mut r PayloadWalker) weighted_temperature() ! {
	r.varint()!
	r.skip(4)!
}

fn (mut r PayloadWalker) overworld_gen_rules() ! {
	for _ in 0 .. 4 {
		r.list(fn (mut w PayloadWalker) ! {
			w.weighted()!
		})!
	}
	for _ in 0 .. 2 {
		r.list(fn (mut w PayloadWalker) ! {
			w.conditional()!
		})!
	}
	r.list(fn (mut w PayloadWalker) ! {
		w.weighted_temperature()!
	})!
}

fn (mut r PayloadWalker) replacement() ! {
	r.skip(2 + 2)!
	r.list(fn (mut w PayloadWalker) ! {
		w.skip(2)!
	})!
	r.skip(4 + 4 + 4)!
}

fn (mut r PayloadWalker) capped_surface() ! {
	for _ in 0 .. 2 {
		r.list(fn (mut w PayloadWalker) ! {
			w.skip(4)!
		})!
	}
	for _ in 0 .. 3 {
		r.optional(fn (mut w PayloadWalker) ! {
			w.skip(4)!
		})!
	}
}

fn (mut r PayloadWalker) noise_block() ! {
	r.text()!
	r.skip(4 + 4 + 4 + 4)!
}

fn (mut r PayloadWalker) noise_gradient_surface() ! {
	r.list(fn (mut w PayloadWalker) ! {
		w.skip(4)!
	})!
	r.list(fn (mut w PayloadWalker) ! {
		w.noise_block()!
	})!
	r.text()!
	r.skip(4)!
	r.list(fn (mut w PayloadWalker) ! {
		w.skip(4)!
	})!
}

fn (mut r PayloadWalker) surface_builder() ! {
	r.optional(fn (mut w PayloadWalker) ! {
		w.surface_material()!
	})!
	r.skip(4)!
	r.optional(fn (mut w PayloadWalker) ! {
		w.skip(4 + 4 + 1 + 1)!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.capped_surface()!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.noise_gradient_surface()!
	})!
}

fn (mut r PayloadWalker) chunk_gen_data() ! {
	r.optional(fn (mut w PayloadWalker) ! {
		w.skip(4 * 4)!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.list(fn (mut x PayloadWalker) ! {
			x.feature()!
		})!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.skip(4 + 5)!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.list(fn (mut x PayloadWalker) ! {
			x.element()!
		})!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.overworld_gen_rules()!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.skip(5 * 4)!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.list(fn (mut x PayloadWalker) ! {
			x.conditional()!
		})!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.list(fn (mut x PayloadWalker) ! {
			x.replacement()!
		})!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.skip(1)!
	})!
	for _ in 0 .. 2 {
		r.optional(fn (mut w PayloadWalker) ! {
			w.surface_builder()!
		})!
	}
}

fn (mut r PayloadWalker) biome() ! {
	r.skip(2 + 2 + 5 * 4 + 4 + 1)!
	r.optional(fn (mut w PayloadWalker) ! {
		w.list(fn (mut x PayloadWalker) ! {
			x.skip(2)!
		})!
	})!
	r.optional(fn (mut w PayloadWalker) ! {
		w.chunk_gen_data()!
	})!
}

fn walk_payload(payload []u8) !PayloadWalker {
	mut r := PayloadWalker{
		data: payload
	}
	biome_count := r.varuint()!
	if biome_count == 0 {
		return error('no biomes')
	}
	for index in 0 .. biome_count {
		r.biome() or { return error('biome ${index}: ${err}') }
	}
	string_count := r.varuint()!
	if string_count == 0 {
		return error('no strings')
	}
	for index in 0 .. string_count {
		r.text() or { return error('string ${index}: ${err}') }
	}
	return r
}

// The payload is walked back exactly the way a client parses it: every biome,
// then the string table, with nothing left over.
fn test_biome_definitions_payload_round_trips() {
	payload := load_biome_definitions(os.join_path('data', 'biome_definitions.nbt')) or {
		assert false, 'failed to load biome definitions: ${err}'
		return
	}
	r := walk_payload(payload) or {
		assert false, '${err}'
		return
	}
	assert r.offset == payload.len
}

// Whatever the registry carries, an expression type is either a real operator
// or the marker. The registry the game ships no longer carries chunk
// generation data, so this only holds the line for the ones that do.
fn test_every_expression_type_in_the_payload_is_an_operator_or_the_marker() {
	payload := load_biome_definitions(os.join_path('data', 'biome_definitions.nbt')) or {
		assert false, 'failed to load biome definitions: ${err}'
		return
	}
	r := walk_payload(payload) or {
		assert false, '${err}'
		return
	}
	for value in r.expression_ops {
		assert value >= -1
	}
}

// A coordinate whose types the document leaves out has to serialise both of
// them as the marker, not as operator zero.
fn test_coordinate_without_types_uses_the_none_marker() {
	mut coordinate := nbt.new_compound()
	coordinate.set('minValue', nbt.Tag(i32(7)))
	coordinate.set('maxValue', nbt.Tag(i32(8)))
	mut w := serializer.new_writer()
	write_coordinate(mut w, coordinate)
	mut r := PayloadWalker{
		data: w.bytes()
	}
	assert r.varint() or { 0 } == -1
	r.skip(2) or { assert false, '${err}' }
	assert r.varint() or { 0 } == -1
}

// The actor registry has to parse and carry the player type, which the client
// resolves its own entity against.
fn test_entity_identifiers_contain_the_player() {
	entries := load_entity_identifiers(os.join_path('data', 'entity_identifiers.nbt')) or {
		assert false, 'failed to load entity identifiers: ${err}'
		return
	}
	assert entries.len > 0
	mut names := []string{cap: entries.len}
	for entry in entries {
		if entry is nbt.Compound {
			if id := entry.get('id') {
				if id is string {
					names << id
				}
			}
		}
	}
	assert 'minecraft:player' in names
}
