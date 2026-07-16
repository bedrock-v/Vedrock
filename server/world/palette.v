module world

import os
import compress.gzip

// BlockVariant is one entry of the canonical block palette - a block name plus
// its state values, every value normalized to its string form so variants can
// be compared and rebuilt regardless of the underlying NBT tag type.
pub struct BlockVariant {
pub:
	name   string
	states map[string]string
}

@[heap]
pub struct BlockPalette {
mut:
	by_id  map[int]BlockVariant
	by_key map[string]int
}

// load_palette reads the gzipped big-endian block palette NBT and indexes every
// block state both by its network id and by its canonical name+states key.
pub fn load_palette(path string) !&BlockPalette {
	raw := os.read_bytes(path)!
	data := gzip.decompress(raw)!
	mut r := NbtReader{
		data: data
	}
	mut p := &BlockPalette{}
	r.read_root(mut p)
	return p
}

pub fn (p &BlockPalette) len() int {
	return p.by_id.len
}

pub fn (p &BlockPalette) variant(id int) ?BlockVariant {
	return p.by_id[id] or { return none }
}

// with_state returns the network id of the same block with one state overridden.
// none when the id is unknown, the block lacks that state, or the resulting
// combination is not in the palette.
pub fn (p &BlockPalette) with_state(id int, key string, value string) ?int {
	v := p.by_id[id] or { return none }
	if key !in v.states {
		return none
	}
	mut states := v.states.clone()
	states[key] = value
	return p.by_key[palette_key(v.name, states)] or { return none }
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
	return (int(r.next()) << 8) | int(r.next())
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
	mut states := map[string]string{}
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
				states[sk] = r.scalar_string(st)
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
	p.by_id[nid] = BlockVariant{
		name:   name
		states: states
	}
	p.by_key[palette_key(name, states)] = nid
}
