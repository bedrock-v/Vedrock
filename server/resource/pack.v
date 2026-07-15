module resource

import os
import crypto.sha256
import compress.szip
import x.json2

// Bedrock caps resource pack chunks at 1 MiB.
pub const pack_chunk_size = 1024 * 1024
// pack_type sent in ResourcePackDataInfo - 6 is a resources pack.
pub const pack_type_resources = 6

// ResourcePack is a single pack the server offers to clients. Local packs carry
// their raw zip bytes for chunked upload; CDN packs carry only a url and let the
// client download the file itself.
@[heap]
pub struct ResourcePack {
pub:
	uuid    string
	version string
	size    u64
	sha256  string
	cdn_url string
mut:
	uuid_raw []u8
	data     []u8
}

pub fn (p &ResourcePack) id() string {
	return '${p.uuid}_${p.version}'
}

pub fn (p &ResourcePack) is_cdn() bool {
	return p.cdn_url != ''
}

pub fn (p &ResourcePack) uuid_bytes() []u8 {
	return p.uuid_raw
}

pub fn (p &ResourcePack) chunk_count() int {
	if p.data.len == 0 {
		return 0
	}
	return (p.data.len + pack_chunk_size - 1) / pack_chunk_size
}

pub fn (p &ResourcePack) chunk(index int) []u8 {
	start := index * pack_chunk_size
	if start < 0 || start >= p.data.len {
		return []u8{}
	}
	mut end := start + pack_chunk_size
	if end > p.data.len {
		end = p.data.len
	}
	return p.data[start..end]
}

// discover lists the pack files (.zip / .mcpack) inside dir.
pub fn discover(dir string) []string {
	mut out := []string{}
	if !os.is_dir(dir) {
		return out
	}
	for entry in os.ls(dir) or { return out } {
		if entry.ends_with('.zip') || entry.ends_with('.mcpack') {
			out << entry
		}
	}
	return out
}

// new_local_pack reads a pack file, extracts its uuid/version from the embedded
// manifest.json and hashes its bytes for the chunked-upload handshake.
pub fn new_local_pack(path string) !&ResourcePack {
	data := os.read_bytes(path)!
	manifest := read_manifest(path)!
	uuid, version := parse_manifest(manifest)!
	raw := uuid_to_bytes(uuid) or { return error('invalid uuid ${uuid}') }
	return &ResourcePack{
		uuid:     uuid
		version:  version
		size:     u64(data.len)
		sha256:   sha256.sum(data).bytestr()
		uuid_raw: raw
		data:     data
	}
}

// new_cdn_pack builds a pack the client downloads from a url instead of over the
// wire. size may be 0 when unknown.
pub fn new_cdn_pack(uuid string, version string, url string, size u64) !&ResourcePack {
	raw := uuid_to_bytes(uuid) or { return error('invalid uuid ${uuid}') }
	return &ResourcePack{
		uuid:     uuid
		version:  version
		size:     size
		cdn_url:  url
		uuid_raw: raw
	}
}

fn read_manifest(path string) !string {
	mut z := szip.open(path, .no_compression, .read_only)!
	defer {
		z.close()
	}
	total := z.total()!
	mut best := ''
	for i in 0 .. total {
		z.open_entry_by_index(i)!
		name := z.name()
		if name == 'manifest.json' || name.ends_with('/manifest.json') {
			size := int(z.size())
			mut buf := []u8{len: size}
			z.read_entry_buf(buf.data, size)!
			z.close_entry()
			content := buf.bytestr()
			if name == 'manifest.json' {
				return content
			}
			// Keep the shallowest manifest as a fallback.
			if best == '' {
				best = content
			}
			continue
		}
		z.close_entry()
	}
	if best != '' {
		return best
	}
	return error('manifest.json not found in ${path}')
}

fn parse_manifest(content string) !(string, string) {
	root := json2.decode[json2.Any](content)!.as_map()
	header := (root['header'] or { return error('manifest has no header') }).as_map()
	uuid := (header['uuid'] or { return error('manifest header has no uuid') }).str()
	mut version := '1.0.0'
	if v := header['version'] {
		parts := v.as_array()
		if parts.len > 0 {
			mut nums := []string{}
			for part in parts {
				nums << part.int().str()
			}
			version = nums.join('.')
		}
	}
	return uuid, version
}

fn uuid_to_bytes(uuid string) ?[]u8 {
	hex := uuid.replace('-', '')
	if hex.len != 32 {
		return none
	}
	mut out := []u8{len: 16}
	for i in 0 .. 16 {
		high := hex_val(hex[i * 2]) or { return none }
		low := hex_val(hex[i * 2 + 1]) or { return none }
		out[i] = (u8(high) << 4) | u8(low)
	}
	return out
}

fn hex_val(c u8) ?int {
	return match c {
		`0`...`9` { int(c - `0`) }
		`a`...`f` { int(c - `a` + 10) }
		`A`...`F` { int(c - `A` + 10) }
		else { none }
	}
}
