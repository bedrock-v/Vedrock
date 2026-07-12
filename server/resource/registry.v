module resource

@[heap]
pub struct PackRegistry {
pub mut:
	packs       []&ResourcePack
	must_accept bool
mut:
	by_id map[string]&ResourcePack
}

pub fn (mut r PackRegistry) add(pack &ResourcePack) {
	r.packs << pack
	r.by_id[pack.id()] = pack
}

pub fn (mut r PackRegistry) set_must_accept(value bool) {
	// Forcing packs only makes sense when there is at least one to force.
	r.must_accept = value && r.packs.len > 0
}

pub fn (r &PackRegistry) is_empty() bool {
	return r.packs.len == 0
}

// find resolves a pack from an id the client sends. The id is normally
// "uuid_version"; fall back to matching the uuid alone.
pub fn (r &PackRegistry) find(id string) ?&ResourcePack {
	if pack := r.by_id[id] {
		return pack
	}
	uuid := id.all_before('_')
	for pack in r.packs {
		if pack.uuid == uuid {
			return pack
		}
	}
	return none
}

// parse_cdn_packs decodes the vedrock.yml cdn-packs value. Format:
//   uuid,version,url,size ; uuid,version,url,size
// size is optional. Malformed entries are skipped.
pub fn parse_cdn_packs(encoded string) []&ResourcePack {
	mut out := []&ResourcePack{}
	if encoded.trim_space() == '' {
		return out
	}
	for raw in encoded.split(';') {
		entry := raw.trim_space()
		if entry == '' {
			continue
		}
		fields := entry.split(',')
		if fields.len < 3 {
			continue
		}
		mut size := u64(0)
		if fields.len >= 4 {
			size = fields[3].trim_space().u64()
		}
		pack := new_cdn_pack(fields[0].trim_space(), fields[1].trim_space(), fields[2].trim_space(),
			size) or { continue }
		out << pack
	}
	return out
}
