module world

import os
import server.internal.gamedata

// BlockVariant is one entry of the canonical block palette - a block name plus
// its state values, every value normalized to its string form so variants can
// be compared and rebuilt regardless of the underlying NBT tag type.
pub struct BlockVariant {
pub:
	name   string
	states BlockStates
}

// BlockStates is one entry's state values, addressed as a slice of the
// palette's shared, interned pair table rather than owning a map.
//
// The vanilla palette is ~23k entries over ~1k distinct names and a few hundred
// distinct state keys and values. Giving each entry its own map[string]string
// cost about 29MB, nearly all of it map overhead and re-allocated copies of the
// same handful of strings. Interning brings the whole palette under 2MB and
// answers the same lookups.
pub struct BlockStates {
	palette &BlockPalette = unsafe { nil }
	start   u32
	count   u32
}

// StatePair is one key/value, both as indices into BlockPalette.strings.
struct StatePair {
	key   u32
	value u32
}

// PaletteEntry is one block state: its name, and where its pairs live in the
// palette's flat pair table.
struct PaletteEntry {
	name  u32
	start u32
	count u32
}

// KeyRef maps a canonical name+states key to its entry, by hash. Kept sorted
// by hash so a lookup is a binary search instead of a 23k-entry string map.
// Hits are always confirmed against the rebuilt key, so a hash collision costs
// a comparison rather than a wrong block.
struct KeyRef {
	hash  u64
	entry u32
}

// IdRef maps a network id to its entry. Kept sorted by id.
struct IdRef {
	id    int
	entry u32
}

@[heap]
pub struct BlockPalette {
mut:
	strings  []string
	interned map[string]u32
	pairs    []StatePair
	entries  []PaletteEntry
	// by_id is sorted by network id. A map keyed on 23k ints costs several MB in
	// bucket metadata alone; a packed, sorted array is a few hundred kB and a
	// binary search.
	by_id []IdRef
	ids   []int
	keys  []KeyRef
}

// intern returns s's index in the shared string table, adding it on first use.
fn (mut p BlockPalette) intern(s string) u32 {
	if index := p.interned[s] {
		return index
	}
	index := u32(p.strings.len)
	p.strings << s
	p.interned[s] = index
	return index
}

// seal drops the interning map once loading is done. It exists only to
// deduplicate during the load and is dead weight afterwards.
fn (mut p BlockPalette) seal() {
	p.keys.sort(a.hash < b.hash)
	p.by_id.sort(a.id < b.id)
	p.interned = map[string]u32{}
	// Every table above was grown by appending, so each one is sitting in the
	// next power of two - 84525 pairs in room for 131072, and so on. None of
	// them is ever appended to again.
	p.strings = tighten(p.strings)
	p.pairs = tighten(p.pairs)
	p.entries = tighten(p.entries)
	p.by_id = tighten(p.by_id)
	p.ids = tighten(p.ids)
	p.keys = tighten(p.keys)
}

// tighten returns a copy of a sized exactly to its length, shedding the spare
// capacity appending left behind. clone() keeps the capacity, so it cannot.
fn tighten[T](a []T) []T {
	mut out := []T{cap: a.len}
	for v in a {
		out << v
	}
	return out
}

// entry_index finds id's entry through the sorted id index.
fn (p &BlockPalette) entry_index(id int) ?u32 {
	mut low := 0
	mut high := p.by_id.len
	for low < high {
		mid := (low + high) / 2
		if p.by_id[mid].id < id {
			low = mid + 1
		} else {
			high = mid
		}
	}
	if low < p.by_id.len && p.by_id[low].id == id {
		return p.by_id[low].entry
	}
	return none
}

// get returns the value of state key, or none when the entry has no such state.
pub fn (s BlockStates) get(key string) ?string {
	if isnil(s.palette) {
		return none
	}
	for i in s.start .. s.start + s.count {
		pair := s.palette.pairs[i]
		if s.palette.strings[pair.key] == key {
			return s.palette.strings[pair.value]
		}
	}
	return none
}

// has reports whether the entry carries state key at all, which is what decides
// whether with_state can rebuild it.
pub fn (s BlockStates) has(key string) bool {
	s.get(key) or { return false }
	return true
}

pub fn (s BlockStates) len() int {
	return int(s.count)
}

// load_palette reads the gzipped big-endian block palette NBT and indexes every
// block state both by its network id and by its canonical name+states key.
pub fn load_palette(path string) !&BlockPalette {
	return parse_palette(gamedata.gunzip(os.read_bytes(path)!)!)
}

// parse_palette indexes an already decompressed palette NBT. Boot decompresses
// the file once and hands the same bytes to every consumer - it is several MB
// expanded, and gunzipping it twice was the largest single spike in the
// process's memory profile.
pub fn parse_palette(data []u8) !&BlockPalette {
	mut r := NbtReader{
		data: data
	}
	mut p := &BlockPalette{}
	r.read_root(mut p)
	p.seal()
	return p
}

pub fn (p &BlockPalette) len() int {
	return p.entries.len
}

pub fn (p &BlockPalette) variant(id int) ?BlockVariant {
	index := p.entry_index(id)?
	entry := p.entries[index]
	return BlockVariant{
		name:   p.strings[entry.name]
		states: BlockStates{
			palette: p
			start:   entry.start
			count:   entry.count
		}
	}
}

// with_state returns the network id of the same block with one state overridden.
// none when the id is unknown, the block lacks that state, or the resulting
// combination is not in the palette.
pub fn (p &BlockPalette) with_state(id int, key string, value string) ?int {
	index := p.entry_index(id)?
	entry := p.entries[index]
	if !p.entry_has_state(entry, key) {
		return none
	}
	wanted := p.entry_key(entry, key, value)
	return p.id_for_key(wanted)
}

// id_for resolves a block name plus an exact set of state values to its network
// id, for callers that build a target state rather than deriving it from an
// existing one.
pub fn (p &BlockPalette) id_for(name string, states map[string]string) ?int {
	return p.id_for_key(palette_key(name, states))
}

fn (p &BlockPalette) entry_has_state(entry PaletteEntry, key string) bool {
	for i in entry.start .. entry.start + entry.count {
		if p.strings[p.pairs[i].key] == key {
			return true
		}
	}
	return false
}

// entry_key renders entry's canonical key, with override_key replaced by
// override_value when the entry carries it. An empty override_key renders the
// entry as stored.
fn (p &BlockPalette) entry_key(entry PaletteEntry, override_key string, override_value string) string {
	mut keys := []string{cap: int(entry.count)}
	mut values := map[string]string{}
	for i in entry.start .. entry.start + entry.count {
		pair := p.pairs[i]
		k := p.strings[pair.key]
		keys << k
		values[k] = if k == override_key { override_value } else { p.strings[pair.value] }
	}
	keys.sort()
	mut parts := []string{cap: keys.len}
	for k in keys {
		parts << '${k}=${values[k]}'
	}
	return '${p.strings[entry.name]}|${parts.join(';')}'
}

// id_for_key resolves a canonical key through the sorted hash index. Every
// candidate sharing the hash is confirmed by rebuilding its key, so a collision
// can only cost a comparison.
fn (p &BlockPalette) id_for_key(wanted string) ?int {
	hash := key_hash(wanted)
	mut low := 0
	mut high := p.keys.len
	for low < high {
		mid := (low + high) / 2
		if p.keys[mid].hash < hash {
			low = mid + 1
		} else {
			high = mid
		}
	}
	for i := low; i < p.keys.len && p.keys[i].hash == hash; i++ {
		index := p.keys[i].entry
		if p.entry_key(p.entries[index], '', '') == wanted {
			return p.ids[index]
		}
	}
	return none
}

fn palette_key(name string, states map[string]string) string {
	mut keys := states.keys()
	keys.sort()
	mut parts := []string{cap: keys.len}
	for k in keys {
		parts << '${k}=${states[k]}'
	}
	return '${name}|${parts.join(';')}'
}

// key_hash is FNV-1a. Collisions are tolerated - id_for_key confirms every hit
// against the real key - so only its spread matters here.
fn key_hash(s string) u64 {
	mut h := u64(0xcbf29ce484222325)
	for c in s {
		h ^= u64(c)
		h *= u64(0x100000001b3)
	}
	return h
}

// NbtReader is a minimal big-endian NBT cursor - only the tags present in the
// block palette are decoded, the rest are skipped.
struct NbtReader {
	data []u8
mut:
	pos int
}

fn (mut r NbtReader) next() u8 {
	b := r.data[r.pos]
	r.pos++
	return b
}

fn (mut r NbtReader) u16be() int {
	return int((u16(r.next()) << 8) | u16(r.next()))
}

fn (mut r NbtReader) i32be() int {
	v := (u32(r.next()) << 24) | (u32(r.next()) << 16) | (u32(r.next()) << 8) | u32(r.next())
	return int(v)
}

fn (mut r NbtReader) str() string {
	l := r.u16be()
	s := r.data[r.pos..r.pos + l].bytestr()
	r.pos += l
	return s
}

fn (mut r NbtReader) skip(n int) {
	r.pos += n
}

fn (mut r NbtReader) skip_value(tid u8) {
	match tid {
		1 { r.skip(1) }
		2 { r.skip(2) }
		3 { r.skip(4) }
		4 { r.skip(8) }
		5 { r.skip(4) }
		6 { r.skip(8) }
		8 { r.skip(r.u16be()) }
		10 { r.skip_compound() }
		9 { r.skip_list() }
		else {}
	}
}

fn (mut r NbtReader) skip_compound() {
	for {
		tid := r.next()
		if tid == 0 {
			return
		}
		r.str()
		r.skip_value(tid)
	}
}

fn (mut r NbtReader) skip_list() {
	etype := r.next()
	count := r.i32be()
	for _ in 0 .. count {
		r.skip_value(etype)
	}
}

// scalar_string renders a scalar tag value as a string, matching how states are
// later rebuilt for lookup. Non-scalar tags are skipped and return ''.
fn (mut r NbtReader) scalar_string(tid u8) string {
	return match tid {
		1 {
			int(i8(r.next())).str()
		}
		2 {
			i16(r.u16be()).str()
		}
		3 {
			r.i32be().str()
		}
		8 {
			r.str()
		}
		else {
			r.skip_value(tid)
			''
		}
	}
}

fn (mut r NbtReader) read_root(mut p BlockPalette) {
	if r.next() != 0x0a {
		return
	}
	r.str() // root name
	for {
		tid := r.next()
		if tid == 0 {
			return
		}
		key := r.str()
		if tid == 9 && key == 'blocks' {
			etype := r.next()
			count := r.i32be()
			for _ in 0 .. count {
				if etype == 0x0a {
					r.read_entry(mut p)
				} else {
					r.skip_value(etype)
				}
			}
		} else {
			r.skip_value(tid)
		}
	}
}

fn (mut r NbtReader) read_entry(mut p BlockPalette) {
	mut nid := 0
	mut name := ''
	start := u32(p.pairs.len)
	for {
		tid := r.next()
		if tid == 0 {
			break
		}
		key := r.str()
		if tid == 0x0a && key == 'states' {
			for {
				st := r.next()
				if st == 0 {
					break
				}
				sk := r.str()
				sv := r.scalar_string(st)
				p.pairs << StatePair{
					key:   p.intern(sk)
					value: p.intern(sv)
				}
			}
			continue
		}
		match tid {
			3 {
				v := r.i32be()
				if key == 'network_id' {
					nid = v
				}
			}
			8 {
				v := r.str()
				if key == 'name' {
					name = v
				}
			}
			else {
				r.skip_value(tid)
			}
		}
	}
	entry := PaletteEntry{
		name:  p.intern(name)
		start: start
		count: u32(p.pairs.len) - start
	}
	index := u32(p.entries.len)
	p.entries << entry
	p.ids << nid
	p.by_id << IdRef{
		id:    nid
		entry: index
	}
	p.keys << KeyRef{
		hash:  key_hash(p.entry_key(entry, '', ''))
		entry: index
	}
}
