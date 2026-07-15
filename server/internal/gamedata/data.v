module gamedata

import os
import compress.gzip
import encoding.base64
import x.json2

pub struct ItemEntry {
pub:
	name            string
	runtime_id      int
	version         int
	component_based bool
}

pub struct CreativeGroup {
pub:
	category              int
	name                  string
	icon_numeric_id       int
	icon_block_runtime_id int
}

pub struct CreativeItem {
pub:
	numeric_id       int
	block_runtime_id int
	meta             int
	group_index      int
}

pub struct GameData {
pub:
	item_entries    []ItemEntry
	creative_groups []CreativeGroup
	creative_items  []CreativeItem
	block_palette   []BlockPaletteEntry
pub mut:
	item_id_by_name  map[string]int
	item_id_by_block map[int]int
}

fn any_str(values map[string]json2.Any, key string) string {
	if key in values {
		return (values[key] or { json2.Any('') }).str()
	}
	return ''
}

fn any_int(values map[string]json2.Any, key string) int {
	if key in values {
		return (values[key] or { json2.Any(0) }).int()
	}
	return 0
}

pub fn load(data_dir string) !GameData {
	mut entries := []ItemEntry{}
	mut id_by_name := map[string]int{}
	mut component_by_name := map[string]bool{}
	palette_doc :=
		json2.decode[json2.Any](os.read_file(os.join_path(data_dir, 'item_palette.json'))!)!.as_map()
	for any_item in (palette_doc['items'] or { json2.Any('') }).as_array() {
		m := any_item.as_map()
		name := any_str(m, 'name')
		runtime_id := any_int(m, 'id')
		component_based := (m['component_based'] or { json2.Any(false) }).bool()
		entries << ItemEntry{
			name:            name
			runtime_id:      runtime_id
			version:         any_int(m, 'version')
			component_based: component_based
		}
		id_by_name[name] = runtime_id
		component_by_name[name] = component_based
	}

	mut groups := []CreativeGroup{}
	mut creative := []CreativeItem{}
	creative_doc := json2.decode[json2.Any](os.read_file(os.join_path(data_dir,
		'creative_items.json'))!)!.as_map()
	for any_group in (creative_doc['groups'] or { json2.Any('') }).as_array() {
		g := any_group.as_map()
		mut icon_id := 0
		mut icon_block := 0
		if 'icon' in g {
			icon := (g['icon'] or { json2.Any('') }).as_map()
			icon_id = id_by_name[any_str(icon, 'id')] or { 0 }
			icon_b64 := any_str(icon, 'block_state_b64')
			if icon_b64 != '' {
				icon_block = block_network_id_from_nbt(base64.decode(icon_b64)) or { 0 }
			}
		}
		groups << CreativeGroup{
			category:              any_int(g, 'creative_category')
			name:                  any_str(g, 'name')
			icon_numeric_id:       icon_id
			icon_block_runtime_id: icon_block
		}
	}
	for any_item in (creative_doc['items'] or { json2.Any('') }).as_array() {
		m := any_item.as_map()
		name := any_str(m, 'id')
		numeric_id := id_by_name[name] or { continue }
		if component_by_name[name] or { false } {
			continue
		}
		mut block_runtime_id := 0
		b64 := any_str(m, 'block_state_b64')
		if b64 != '' {
			block_runtime_id = block_network_id_from_nbt(base64.decode(b64)) or { 0 }
		}
		creative << CreativeItem{
			numeric_id:       numeric_id
			block_runtime_id: block_runtime_id
			meta:             any_int(m, 'damage')
			group_index:      any_int(m, 'group_index')
		}
	}

	mut id_by_block := map[int]int{}
	for item in creative {
		if item.block_runtime_id != 0 && item.block_runtime_id !in id_by_block {
			id_by_block[item.block_runtime_id] = item.numeric_id
		}
	}

	compressed := os.read_bytes(os.join_path(data_dir, 'block_palette.nbt'))!
	block_palette := parse_block_palette(gzip.decompress(compressed)!)!

	return GameData{
		item_entries:     entries
		creative_groups:  groups
		creative_items:   creative
		block_palette:    block_palette
		item_id_by_name:  id_by_name
		item_id_by_block: id_by_block
	}
}

pub fn (d &GameData) item_for_block(block_runtime_id int) int {
	return d.item_id_by_block[block_runtime_id] or { 0 }
}

pub fn (d &GameData) item_name(id int) string {
	for name, item_id in d.item_id_by_name {
		if item_id == id {
			return name
		}
	}
	return ''
}

pub fn (d &GameData) item_id(name string) int {
	return d.item_id_by_name[name] or { 0 }
}
