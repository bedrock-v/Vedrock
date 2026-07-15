module session

import protocol
import protocol.types
import nbt
import server.player.playerdb

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

fn wrap_stack_id(stack types.ItemStack, net_id int) types.ItemStackWrapper {
	return types.ItemStackWrapper{
		stack_id:         net_id
		stack_id_variant: 0
		item_stack:       stack
	}
}

fn empty_stack() types.ItemStackWrapper {
	return wrap_stack(types.ItemStack{})
}

fn (s &NetworkSession) max_stack_size_for_numeric(id int) int {
	name := s.hub.data.item_name(id)
	if name == '' {
		return 64
	}
	return s.hub.items.max_stack_size(name)
}

fn (s &NetworkSession) clamp_stack_count(id int, count int) int {
	if count <= 0 {
		return 0
	}
	max := s.max_stack_size_for_numeric(id)
	if count > max {
		return max
	}
	return count
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

fn (mut s NetworkSession) restore_inventory() &protocol.InventoryContentPacket {
	mut items := []types.ItemStackWrapper{}
	for i in 0 .. inventory_slot_count {
		if i < s.loaded_items.len {
			saved := s.loaded_items[i]
			count := s.clamp_stack_count(saved.id, saved.count)
			if count <= 0 {
				items << empty_stack()
				continue
			}
			stack := types.ItemStack{
				id:               saved.id
				meta:             saved.meta
				count:            count
				block_runtime_id: saved.block_runtime_id
				raw_extra_data:   []u8{}
			}
			net_id := s.track_stack(stack)
			s.inv_slots[i] = net_id
			items << wrap_stack_id(stack, net_id)
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

fn (mut s NetworkSession) save_player_data() {
	mut items := []playerdb.InvItem{}
	for _, stack in s.inv_stacks {
		count := s.clamp_stack_count(stack.id, stack.count)
		if count <= 0 {
			continue
		}
		items << playerdb.InvItem{
			id:               stack.id
			meta:             stack.meta
			count:            count
			block_runtime_id: stack.block_runtime_id
		}
	}
	playerdb.save_player(players_dir, s.player_key(), playerdb.PlayerData{
		x:        s.position.x
		y:        s.position.y
		z:        s.position.z
		yaw:      s.yaw
		pitch:    s.pitch
		gamemode: s.game_mode
		items:    items
	}) or { s.log.warn('Failed to save player ${s.player_key()}: ${err}') }
}
