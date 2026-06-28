module session

import protocol
import protocol.types
import nbt
import world

const creative_category_construction = 1
const inventory_window_id = 0
const inventory_slot_count = 36

struct ItemType {
	string_id        string
	numeric_id       int
	block_network_id int
}

const item_catalog = [
	ItemType{'minecraft:stone', 1, world.stone.network_id},
	ItemType{'minecraft:grass_block', 2, world.grass_block.network_id},
	ItemType{'minecraft:diamond_sword', 3, 0},
	ItemType{'minecraft:diamond_pickaxe', 4, 0},
	ItemType{'minecraft:diamond_axe', 5, 0},
	ItemType{'minecraft:apple', 6, 0},
	ItemType{'minecraft:bread', 7, 0},
	ItemType{'minecraft:torch', 8, 0},
]

fn empty_component_nbt() nbt.RootTag {
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(nbt.new_compound())
	}
}

fn make_item_stack(item ItemType, count int) types.ItemStack {
	return types.ItemStack{
		id:               item.numeric_id
		meta:             0
		count:            count
		block_runtime_id: item.block_network_id
		raw_extra_data:   []u8{}
	}
}

fn wrap_stack(stack types.ItemStack) types.ItemStackWrapper {
	return types.ItemStackWrapper{
		stack_id:         0
		stack_id_variant: 0
		item_stack:       stack
	}
}

fn empty_stack() types.ItemStackWrapper {
	return wrap_stack(types.ItemStack{})
}

fn item_registry() &protocol.ItemRegistryPacket {
	mut entries := []types.ItemTypeEntry{}
	for item in item_catalog {
		entries << types.ItemTypeEntry{
			string_id:       item.string_id
			numeric_id:      item.numeric_id
			component_based: false
			version:         0
			component_nbt:   empty_component_nbt()
		}
	}
	return &protocol.ItemRegistryPacket{
		entries: entries
	}
}

fn creative_content() &protocol.CreativeContentPacket {
	mut items := []types.CreativeItemEntry{}
	for index, item in item_catalog {
		items << types.CreativeItemEntry{
			entry_id: index + 1
			item:     make_item_stack(item, 1)
			group_id: 0
		}
	}
	return &protocol.CreativeContentPacket{
		groups: [
			types.CreativeGroupEntry{
				category_id:   creative_category_construction
				category_name: ''
				icon:          make_item_stack(item_catalog[0], 1)
			},
		]
		items:  items
	}
}

fn starter_inventory() &protocol.InventoryContentPacket {
	mut items := []types.ItemStackWrapper{}
	for i in 0 .. inventory_slot_count {
		if i < item_catalog.len {
			count := if item_catalog[i].block_network_id != 0 { 64 } else { 1 }
			items << wrap_stack(make_item_stack(item_catalog[i], count))
		} else {
			items << empty_stack()
		}
	}
	return &protocol.InventoryContentPacket{
		window_id:      inventory_window_id
		items:          items
		container_name: types.FullContainerName{
			container_id: 0
		}
		storage:        empty_stack()
	}
}
