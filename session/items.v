module session

import protocol
import protocol.types
import nbt

const inventory_window_id = 0
const inventory_slot_count = 36
const starter_item_count = 9

fn empty_component_nbt() nbt.RootTag {
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(nbt.new_compound())
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

fn (s &NetworkSession) item_registry() &protocol.ItemRegistryPacket {
	mut entries := []types.ItemTypeEntry{}
	for entry in s.hub.data.item_entries {
		entries << types.ItemTypeEntry{
			string_id:       entry.name
			numeric_id:      entry.runtime_id
			component_based: entry.component_based
			version:         entry.version
			component_nbt:   empty_component_nbt()
		}
	}
	return &protocol.ItemRegistryPacket{
		entries: entries
	}
}

fn (s &NetworkSession) creative_content() &protocol.CreativeContentPacket {
	mut groups := []types.CreativeGroupEntry{}
	for group in s.hub.data.creative_groups {
		groups << types.CreativeGroupEntry{
			category_id:   group.category
			category_name: group.name
			icon:          types.ItemStack{
				id:               group.icon_numeric_id
				count:            1
				block_runtime_id: group.icon_block_runtime_id
				raw_extra_data:   []u8{}
			}
		}
	}
	mut items := []types.CreativeItemEntry{}
	for index, item in s.hub.data.creative_items {
		items << types.CreativeItemEntry{
			entry_id: index + 1
			item:     types.ItemStack{
				id:               item.numeric_id
				meta:             item.meta
				count:            1
				block_runtime_id: item.block_runtime_id
				raw_extra_data:   []u8{}
			}
			group_id: item.group_index
		}
	}
	return &protocol.CreativeContentPacket{
		groups: groups
		items:  items
	}
}

fn (s &NetworkSession) starter_inventory() &protocol.InventoryContentPacket {
	creative := s.hub.data.creative_items
	mut items := []types.ItemStackWrapper{}
	for i in 0 .. inventory_slot_count {
		if i < starter_item_count && i < creative.len {
			item := creative[i]
			items << wrap_stack(types.ItemStack{
				id:               item.numeric_id
				meta:             item.meta
				count:            1
				block_runtime_id: item.block_runtime_id
				raw_extra_data:   []u8{}
			})
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
