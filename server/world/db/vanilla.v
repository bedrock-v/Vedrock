module db

import sync
import server.world
import server.world.upgrader

const block_upgrader = upgrader.default_upgrader()

const subchunk_tag = u8(0x2f)

fn subchunk_key(cx int, cz int, y_index int, dim world.Dimension) []u8 {
	mut b := []u8{}
	put_i32(mut b, cx)
	put_i32(mut b, cz)
	if dim.id != 0 {
		put_i32(mut b, dim.id)
	}
	b << subchunk_tag
	b << u8(i8(y_index))
	return b
}

pub fn (w &WorldStore) load_chunk(cx int, cz int) ?world.Chunk {
	mut chunk := world.new_chunk_dim(w.dimension)
	min_y_index := w.dimension.min_y / 16
	max_y_index := min_y_index + w.dimension.subchunk_count - 1
	mut found := false
	for y_index in min_y_index .. max_y_index + 1 {
		data := w.db.get(subchunk_key(cx, cz, y_index, w.dimension)) or { continue }
		ids := decode_subchunk(data) or { continue }
		chunk.set_section(y_index - min_y_index, ids)
		found = true
	}
	if !found {
		return none
	}
	return chunk
}

struct SubchunkReader {
	data []u8
mut:
	offset int
}

fn (mut r SubchunkReader) u8() !u8 {
	if r.offset >= r.data.len {
		return error('subchunk: unexpected end of data')
	}
	b := r.data[r.offset]
	r.offset++
	return b
}

fn (mut r SubchunkReader) u16_le() !u16 {
	lo := r.u8()!
	hi := r.u8()!
	return u16(lo) | (u16(hi) << 8)
}

fn (mut r SubchunkReader) i32_le() !int {
	mut v := u32(0)
	for i in 0 .. 4 {
		v |= u32(r.u8()!) << (i * 8)
	}
	return int(v)
}

fn (mut r SubchunkReader) str_le() !string {
	length := int(r.u16_le()!)
	if r.offset + length > r.data.len {
		return error('subchunk: string exceeds data')
	}
	s := r.data[r.offset..r.offset + length].bytestr()
	r.offset += length
	return s
}

fn decode_subchunk(data []u8) ![]int {
	mut r := SubchunkReader{
		data: data
	}
	version := r.u8()!
	mut storage_count := 1
	match version {
		1 {}
		8 {
			storage_count = int(r.u8()!)
		}
		9 {
			storage_count = int(r.u8()!)
			r.u8()!
		}
		else {
			return error('subchunk: unsupported version ${version}')
		}
	}

	if storage_count < 1 {
		return error('subchunk: no block storages')
	}
	return decode_block_storage(mut r)!
}

fn decode_block_storage(mut r SubchunkReader) ![]int {
	header := r.u8()!
	bits := int(header >> 1)
	mut indices := []int{len: 4096}
	if bits > 0 {
		if 32 % bits != 0 && bits !in [3, 5, 6] {
			return error('subchunk: invalid bits per block ${bits}')
		}
		per_word := 32 / bits
		word_count := (4096 + per_word - 1) / per_word
		mask := (1 << bits) - 1
		mut words := []u32{len: word_count}
		for i in 0 .. word_count {
			words[i] = u32(r.i32_le()!)
		}
		for i in 0 .. 4096 {
			word := words[i / per_word]
			indices[i] = int((word >> ((i % per_word) * bits)) & u32(mask))
		}
	}
	mut palette_count := 1
	if bits > 0 {
		palette_count = r.i32_le()!
	}
	if palette_count < 1 || palette_count > 4096 {
		return error('subchunk: invalid palette size ${palette_count}')
	}
	mut palette := []int{len: palette_count}
	for i in 0 .. palette_count {
		palette[i] = read_palette_entry(mut r)!
	}
	mut ids := []int{len: 4096}
	for i in 0 .. 4096 {
		index := indices[i]
		if index >= palette_count {
			return error('subchunk: palette index out of range')
		}
		ids[i] = palette[index]
	}
	return ids
}

fn read_palette_entry(mut r SubchunkReader) !int {
	tag := r.u8()!
	if tag != 0x0a {
		return error('subchunk: palette entry is not a compound')
	}
	r.str_le()!
	mut name := ''
	mut states := []world.BlockState{}
	mut version := 0
	for {
		field_tag := r.u8()!
		if field_tag == 0x00 {
			break
		}
		key := r.str_le()!
		match field_tag {
			0x03 {
				value := r.i32_le()!
				if key == 'version' {
					version = value
				}
			}
			0x08 {
				value := r.str_le()!
				if key == 'name' {
					name = value
				}
			}
			0x0a {
				if key == 'states' {
					states = read_states(mut r)!
				} else {
					skip_compound(mut r)!
				}
			}
			else {
				return error('subchunk: unsupported nbt tag ${field_tag}')
			}
		}
	}
	if name == '' {
		return error('subchunk: palette entry missing block name')
	}
	upgraded := block_upgrader.upgrade(upgrader.from_world(name, states, version))
	return world.new_block_with_states(upgraded.name, upgraded.to_world()).network_id
}

fn read_states(mut r SubchunkReader) ![]world.BlockState {
	mut states := []world.BlockState{}
	for {
		tag := r.u8()!
		if tag == 0x00 {
			break
		}
		key := r.str_le()!
		match tag {
			0x01 {
				states << world.BlockState{
					key:        key
					kind:       world.state_kind_byte
					byte_value: r.u8()!
				}
			}
			0x03 {
				states << world.BlockState{
					key:       key
					kind:      world.state_kind_int
					int_value: r.i32_le()!
				}
			}
			0x08 {
				states << world.BlockState{
					key:        key
					kind:       world.state_kind_string
					string_val: r.str_le()!
				}
			}
			else {
				return error('subchunk: unsupported state tag ${tag}')
			}
		}
	}
	return states
}

fn skip_compound(mut r SubchunkReader) ! {
	for {
		tag := r.u8()!
		if tag == 0x00 {
			return
		}
		r.str_le()!
		match tag {
			0x01 {
				r.u8()!
			}
			0x02 {
				r.u16_le()!
			}
			0x03 {
				r.i32_le()!
			}
			0x08 {
				r.str_le()!
			}
			0x0a {
				skip_compound(mut r)!
			}
			else {
				return error('subchunk: unsupported nbt tag ${tag}')
			}
		}
	}
}

@[heap]
struct ChunkCache {
mut:
	mutex  &sync.Mutex = sync.new_mutex()
	chunks map[u64]world.Chunk
	misses map[u64]bool
}

fn chunk_cache_key(cx int, cz int) u64 {
	return (u64(u32(cx)) << 32) | u64(u32(cz))
}

pub struct StoredGenerator {
	store    Provider
	fallback world.Generator
	cache    &ChunkCache
}

pub fn new_stored_generator(store Provider, fallback world.Generator) StoredGenerator {
	return StoredGenerator{
		store:    store
		fallback: fallback
		cache:    &ChunkCache{}
	}
}

fn (g StoredGenerator) cached_chunk(cx int, cz int) ?world.Chunk {
	key := chunk_cache_key(cx, cz)
	mut cache := unsafe { g.cache }
	cache.mutex.lock()
	defer {
		cache.mutex.unlock()
	}
	if key in cache.chunks {
		return cache.chunks[key]
	}
	if key in cache.misses {
		return none
	}
	chunk := g.store.load_chunk(cx, cz) or {
		cache.misses[key] = true
		return none
	}
	cache.chunks[key] = chunk
	return chunk
}

pub fn (g StoredGenerator) spawn_y() int {
	chunk := g.cached_chunk(0, 0) or { return g.fallback.spawn_y() }
	dim := g.store.dimension()
	for y := dim.max_y(); y >= dim.min_y; y-- {
		if chunk.block_id(0, y, 0) != world.air.network_id {
			return y + 1
		}
	}
	return g.fallback.spawn_y()
}

pub fn (g StoredGenerator) uses_blocks() bool {
	if _ := g.cached_chunk(0, 0) {
		return true
	}
	return g.fallback.uses_blocks()
}

pub fn (g StoredGenerator) generate(chunk_x int, chunk_z int) world.Chunk {
	return g.cached_chunk(chunk_x, chunk_z) or { g.fallback.generate(chunk_x, chunk_z) }
}

pub fn (g StoredGenerator) block_at(x int, y int, z int) int {
	chunk := g.cached_chunk(x >> 4, z >> 4) or { return g.fallback.block_at(x, y, z) }
	return chunk.block_id(x & 15, y, z & 15)
}

pub fn (g StoredGenerator) biome_at(x int, z int) int {
	chunk := g.cached_chunk(x >> 4, z >> 4) or { return g.fallback.biome_at(x, z) }
	return chunk.biome_id(x & 15, z & 15)
}

// SubchunkWriter mirrors SubchunkReader: little-endian and only the tags the
// vanilla subchunk format actually uses.
struct SubchunkWriter {
mut:
	data []u8
}

fn (mut w SubchunkWriter) u8(v u8) {
	w.data << v
}

fn (mut w SubchunkWriter) u16_le(v u16) {
	w.data << u8(v)
	w.data << u8(v >> 8)
}

fn (mut w SubchunkWriter) i32_le(v int) {
	u := u32(v)
	w.data << u8(u)
	w.data << u8(u >> 8)
	w.data << u8(u >> 16)
	w.data << u8(u >> 24)
}

fn (mut w SubchunkWriter) str_le(s string) {
	w.u16_le(u16(s.len))
	w.data << s.bytes()
}

// subchunk_bits are the index widths the format allows, narrowest first.
// Anything else is rejected on read, here and by vanilla.
const subchunk_bits = [1, 2, 3, 4, 5, 6, 8, 16]

// bits_for_palette is the narrowest legal width that can address count
// entries. A single entry needs no indices at all which the format spells as
// zero bits and no index words.
fn bits_for_palette(count int) !int {
	if count <= 1 {
		return 0
	}
	for bits in subchunk_bits {
		if (1 << bits) >= count {
			return bits
		}
	}
	return error('subchunk: a palette of ${count} does not fit any index width')
}

// encode_subchunk writes one subchunk in the format decode_subchunk reads,
// which is vanilla's own: a paletted, bit packed index array followed by the
// palette as little-endian NBT. Writing it rather than a private format is what
// keeps a world Vedrock has edited a world anything else can still open.
//
// The palette is needed because a block's network id is a hash of its canonical
// state NBT and can't be turned back into a name and states without it.
fn encode_subchunk(ids []int, y_index int, palette &world.BlockPalette) ![]u8 {
	if ids.len != 4096 {
		return error('subchunk: expected 4096 block ids, got ${ids.len}')
	}
	mut order := []int{}
	mut index_of := map[int]int{}
	mut indices := []int{len: 4096}
	for i, id in ids {
		if id in index_of {
			indices[i] = index_of[id]
			continue
		}
		index_of[id] = order.len
		indices[i] = order.len
		order << id
	}
	bits := bits_for_palette(order.len)!

	mut w := SubchunkWriter{}
	// Version 9 carries the subchunk's own y index, which is what lets a world
	// reach below zero. The key carries it too; vanilla writes both.
	w.u8(9)
	w.u8(1)
	w.u8(u8(i8(y_index)))
	// The low bit of the header says the indices point at a runtime palette
	// rather than the NBT one written below. Ours is always the NBT one.
	w.u8(u8(bits) << 1)
	if bits > 0 {
		per_word := 32 / bits
		word_count := (4096 + per_word - 1) / per_word
		for word_index in 0 .. word_count {
			mut word := u32(0)
			for slot in 0 .. per_word {
				i := word_index * per_word + slot
				if i >= 4096 {
					break
				}
				word |= u32(indices[i]) << (slot * bits)
			}
			w.i32_le(int(word))
		}
		w.i32_le(order.len)
	}
	for id in order {
		write_palette_entry(mut w, id, palette)!
	}
	return w.data
}

// write_palette_entry writes one block as the compound read_palette_entry
// expects. The version is the one the upgrader already considers current, so a
// block written here is not rewritten when it is read back.
fn write_palette_entry(mut w SubchunkWriter, id int, palette &world.BlockPalette) ! {
	variant := palette.variant(id) or {
		return error('subchunk: block id ${id} is not in the palette')
	}
	w.u8(0x0a)
	w.str_le('')
	w.u8(0x08)
	w.str_le('name')
	w.str_le(variant.name)
	w.u8(0x0a)
	w.str_le('states')
	for state in variant.states.to_block_states() {
		match state.kind {
			world.state_kind_string {
				w.u8(0x08)
				w.str_le(state.key)
				w.str_le(state.string_val)
			}
			world.state_kind_int {
				w.u8(0x03)
				w.str_le(state.key)
				w.i32_le(state.int_value)
			}
			else {
				w.u8(0x01)
				w.str_le(state.key)
				w.u8(state.byte_value)
			}
		}
	}
	w.u8(0x00)
	w.u8(0x03)
	w.str_le('version')
	w.i32_le(upgrader.current_version)
	w.u8(0x00)
}
