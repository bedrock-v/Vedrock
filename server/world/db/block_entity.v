module db

import bedrock_v.nbt

// Block entities are stored as one NBT compound each whatever kind they are.
// A sign keeps its text under text_key, a container its contents under
// items_key and a kind added later keeps whatever it needs beside them, which
// is the point of the merge: a new kind costs a key in here and nothing in the
// storage layer.
const block_entity_text_key = 'Text'
const block_entity_items_key = 'Items'

fn encode_block_entity(data nbt.Compound) []u8 {
	return nbt.encode(nbt.RootTag{
		name: ''
		tag:  nbt.Tag(data)
	})
}

fn decode_block_entity(data []u8) ?nbt.Compound {
	result := nbt.decode(data) or { return none }
	tag := result.root.tag
	if tag is nbt.Compound {
		return tag
	}
	return none
}

fn block_entity_text(data nbt.Compound) ?string {
	tag := data.get(block_entity_text_key)?
	if tag is string {
		return tag
	}
	return none
}

fn block_entity_items(data nbt.Compound) []ContainerSlotItem {
	tag := data.get(block_entity_items_key) or { return []ContainerSlotItem{} }
	if tag !is nbt.List {
		return []ContainerSlotItem{}
	}
	list := tag as nbt.List
	mut out := []ContainerSlotItem{cap: list.values.len}
	for entry in list.values {
		if entry !is nbt.Compound {
			continue
		}
		c := entry as nbt.Compound
		out << ContainerSlotItem{
			slot:             compound_int(c, 'Slot')
			id:               compound_int(c, 'Id')
			meta:             compound_int(c, 'Meta')
			count:            compound_int(c, 'Count')
			block_runtime_id: compound_int(c, 'Block')
			raw_extra_data:   compound_bytes(c, 'Extra')
		}
	}
	return out
}

fn items_tag(items []ContainerSlotItem) nbt.Tag {
	mut values := []nbt.Tag{cap: items.len}
	for item in items {
		mut c := nbt.new_compound()
		c.set('Slot', nbt.Tag(i32(item.slot)))
		c.set('Id', nbt.Tag(i32(item.id)))
		c.set('Meta', nbt.Tag(i32(item.meta)))
		c.set('Count', nbt.Tag(i32(item.count)))
		c.set('Block', nbt.Tag(i32(item.block_runtime_id)))
		if item.raw_extra_data.len > 0 {
			c.set('Extra', nbt.Tag(nbt.ByteArray{
				values: item.raw_extra_data.clone()
			}))
		}
		values << nbt.Tag(c)
	}
	return nbt.Tag(nbt.List{
		element_type: nbt.tag_compound
		values:       values
	})
}

fn compound_int(c nbt.Compound, key string) int {
	tag := c.get(key) or { return 0 }
	if tag is i32 {
		return int(tag)
	}
	return 0
}

fn compound_bytes(c nbt.Compound, key string) []u8 {
	tag := c.get(key) or { return []u8{} }
	if tag is nbt.ByteArray {
		return tag.values.clone()
	}
	return []u8{}
}
