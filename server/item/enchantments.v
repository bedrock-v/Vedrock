module item

import server.enchant

const ench_key = 'ench'
const ench_id_key = 'id'
const ench_level_key = 'lvl'

// max_stack_enchantments bounds how many entries are read out of one item's
// enchantment list, so a malformed or hostile stack cannot size an allocation.
const max_stack_enchantments = 64

// enchantments_from_nbt reads the enchantments on an item stack's extra data.
// A stack with none, or with data that does not parse, has none.
pub fn enchantments_from_nbt(raw []u8) []enchant.Applied {
	if raw.len == 0 {
		return []enchant.Applied{}
	}
	mut r := LeNbtReader{
		data: raw
	}
	return parse_item_enchantments(mut r) or { []enchant.Applied{} }
}

// enchantment_level is the level of one enchantment on a stack, or 0 when it
// does not carry it. Callers scale an effect by this directly.
pub fn enchantment_level(raw []u8, name string) int {
	target := enchant.get_by_name(name) or { return 0 }
	for applied in enchantments_from_nbt(raw) {
		if applied.eid == target.id() {
			return applied.level
		}
	}
	return 0
}

// enchanted_nbt returns item extra data carrying entries, keeping nothing else
// the stack had. It is enough for putting enchantments on an item; a stack
// that also carries book pages or a custom name is not merged with it.
pub fn enchanted_nbt(entries []enchant.Applied) []u8 {
	if entries.len == 0 {
		return []u8{}
	}
	mut w := LeNbtWriter{}
	start_item_extra_data(mut w)
	w.u8(nbt_tag_compound)
	w.le_u16(0)
	write_enchantments_field(mut w, entries)
	w.u8(nbt_tag_end)
	end_item_extra_data(mut w)
	return w.data
}

fn write_enchantments_field(mut w LeNbtWriter, entries []enchant.Applied) {
	w.key(nbt_tag_list, ench_key)
	w.u8(nbt_tag_compound)
	w.le_u32(u32(entries.len))
	for entry in entries {
		w.key(nbt_tag_short, ench_id_key)
		w.le_u16(u16(entry.eid))
		w.key(nbt_tag_short, ench_level_key)
		w.le_u16(u16(entry.level))
		w.u8(nbt_tag_end)
	}
}

fn (mut r LeNbtReader) read_enchantment_list() ![]enchant.Applied {
	element_id := r.u8()!
	count := int(r.le_u32()!)
	if count < 0 || count > max_stack_enchantments {
		return error('item nbt: enchantment list length ${count} out of range')
	}
	mut out := []enchant.Applied{cap: count}
	for _ in 0 .. count {
		if element_id != nbt_tag_compound {
			return error('item nbt: unexpected enchantment element type ${element_id}')
		}
		mut eid := 0
		mut level := 0
		for {
			field_id := r.u8()!
			if field_id == nbt_tag_end {
				break
			}
			field_key := r.string()!
			if field_id == nbt_tag_short && field_key == ench_id_key {
				eid = int(r.le_u16()!)
			} else if field_id == nbt_tag_short && field_key == ench_level_key {
				level = int(r.le_u16()!)
			} else {
				r.skip_payload(field_id)!
			}
		}
		if level > 0 {
			out << enchant.Applied{
				eid:   eid
				level: level
			}
		}
	}
	return out
}

fn parse_enchantments(mut r LeNbtReader) ![]enchant.Applied {
	root_id := r.u8()!
	if root_id != nbt_tag_compound {
		return error('item nbt: root is not a compound')
	}
	r.string()!
	for {
		child_id := r.u8()!
		if child_id == nbt_tag_end {
			break
		}
		key := r.string()!
		if child_id == nbt_tag_list && key == ench_key {
			return r.read_enchantment_list()!
		}
		r.skip_payload(child_id)!
	}
	return []enchant.Applied{}
}

fn parse_item_enchantments(mut r LeNbtReader) ![]enchant.Applied {
	flag := r.le_u16()!
	if flag != 0xffff {
		return []enchant.Applied{}
	}
	version := r.u8()!
	if version != 1 {
		return error('item nbt: unexpected item extra data version ${version}')
	}
	return parse_enchantments(mut r)!
}
