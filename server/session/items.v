module session

import protocol.types
import nbt
import server.player.playerdb
import server.item
import server.block
import protocol.current as proto

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
	return item.max_stack_size(name)
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

fn (s &NetworkSession) item_registry() &proto.ItemComponentPacket {
	mut entries := []proto.ItemsEntry{}
	for entry in s.hub.data.item_entries {
		entries << proto.ItemsEntry{
			component_item_name: entry.name
			runtime_id:          i16(entry.runtime_id)
			is_component_based:  entry.component_based
			version:             unsafe { proto.ItemVersion(entry.version) }
			component_data:      empty_component_nbt()
		}
	}
	for def in item.registered_custom() {
		entries << proto.ItemsEntry{
			component_item_name: def.id
			runtime_id:          i16(def.runtime_id)
			is_component_based:  true
			version:             proto.ItemVersion.data_driven
			component_data:      def.components()
		}
	}
	return &proto.ItemComponentPacket{
		items: entries
	}
}

// voxel_shapes is the vanilla shape list with the names the client looks its
// own copies up by.
fn (s &NetworkSession) voxel_shapes() &proto.VoxelShapesPacket {
	loaded := s.hub.data.voxel_shapes
	mut shapes := []proto.VoxelShape{cap: loaded.shapes.len}
	for shape in loaded.shapes {
		shapes << proto.VoxelShape{
			cells:         proto.VoxelCells{
				x_size:  shape.x_size
				y_size:  shape.y_size
				z_size:  shape.z_size
				storage: shape.storage
			}
			x_coordinates: shape.x_coordinates
			y_coordinates: shape.y_coordinates
			z_coordinates: shape.z_coordinates
		}
	}
	mut names := []proto.VoxelShapeNameEntry{cap: loaded.names.len}
	for entry in loaded.names {
		names << proto.VoxelShapeNameEntry{
			name: entry.name
			id:   entry.id
		}
	}
	return &proto.VoxelShapesPacket{
		shapes:   shapes
		name_map: names
	}
}

// custom_block_entries is every block the client has to be told about before
// it can render or place one: the data driven vanilla blocks first, then the
// blocks plugins registered.
fn (s &NetworkSession) custom_block_entries() []proto.BlockProperty {
	defs := block.registered_custom()
	data_driven := s.hub.data.block_definitions
	mut out := []proto.BlockProperty{cap: data_driven.len + defs.len}
	for def in data_driven {
		out << proto.BlockProperty{
			block_name:       def.name
			block_definition: def.properties
		}
	}
	for def in defs {
		entry := def.network_entry()
		out << proto.BlockProperty{
			block_name:       entry.name
			block_definition: entry.properties
		}
	}
	return out
}

fn (s &NetworkSession) creative_content() &proto.CreativeContentPacket {
	mut groups := []proto.CreativeItemGroup{}
	for group in s.hub.data.creative_groups {
		mut icon_id := group.icon_numeric_id
		mut icon_block_runtime_id := group.icon_block_runtime_id
		if icon_id == 0 {
			icon_id = s.hub.data.item_id('minecraft:stone')
			if icon_id == 0 {
				icon_id = 1
			}
			icon_block_runtime_id = 0
		}
		groups << proto.CreativeItemGroup{
			category: unsafe { proto.CreativeItemCategory(group.category) }
			name:     group.name
			icon:     proto.item_instance(types.ItemStack{
				id:               icon_id
				count:            1
				block_runtime_id: icon_block_runtime_id
				raw_extra_data:   []u8{}
			})
		}
	}
	mut items := []proto.CreativeItemData{}
	for index, item in s.hub.data.creative_items {
		items << proto.CreativeItemData{
			creative_net_id: u32(index + 1)
			item_instance:   proto.item_instance(types.ItemStack{
				id:               item.numeric_id
				meta:             item.meta
				count:            1
				block_runtime_id: item.block_runtime_id
				raw_extra_data:   []u8{}
			})
			group_id:        u32(item.group_index)
		}
	}
	mut next_entry := s.hub.data.creative_items.len + 1
	for def in item.registered_custom() {
		items << proto.CreativeItemData{
			creative_net_id: u32(next_entry)
			item_instance:   proto.item_instance(types.ItemStack{
				id:             def.runtime_id
				count:          1
				raw_extra_data: []u8{}
			})
			group_id:        u32(def.creative_group_index)
		}
		next_entry++
	}
	return &proto.CreativeContentPacket{
		groups:   groups
		contents: items
	}
}

fn (mut s NetworkSession) restore_inventory() &proto.InventoryContentPacket {
	mut items := []proto.NetworkItemStackDescriptorV2{}
	mut loaded_by_slot := map[int]playerdb.InvItem{}
	for i in 0 .. s.player.loaded_items_len() {
		saved := s.player.loaded_item(i)
		slot := if saved.slot >= 0 { saved.slot } else { i }
		if slot >= 0 && slot < inventory_slot_count {
			loaded_by_slot[slot] = saved
		}
	}
	for i in 0 .. inventory_slot_count {
		if saved := loaded_by_slot[i] {
			count := s.clamp_stack_count(saved.id, saved.count)
			if count <= 0 {
				items << proto.item_descriptor_v2(types.ItemStack{})
				continue
			}
			stack := types.ItemStack{
				id:               saved.id
				meta:             saved.meta
				count:            count
				block_runtime_id: saved.block_runtime_id
				raw_extra_data:   saved.raw_extra_data.clone()
			}
			net_id := s.player.track_stack(stack)
			s.player.set_slot(i, net_id)
			items << proto.item_descriptor_v2_tracked(stack, net_id)
		} else {
			items << proto.item_descriptor_v2(types.ItemStack{})
		}
	}
	return &proto.InventoryContentPacket{
		inventory_id:        u32(inventory_window_id)
		slots:               items
		container_name_data: proto.FullContainerName{
			container: .inventory_container
		}
		storage_item:        proto.item_descriptor_v2(types.ItemStack{})
	}
}

// save_player_data reads inventory, position and status through their own
// Player locks during disconnect. This is not one atomic snapshot across all
// fields; a task that lands during disconnect may make one saved field fresher
// than another. The consequence is limited to minor persisted staleness.
fn (mut s NetworkSession) save_player_data() {
	mut items := []playerdb.InvItem{}
	slot_stacks := s.player.snapshot_slot_stacks()
	for slot in 0 .. inventory_slot_count {
		stack := slot_stacks[slot] or { continue }
		count := s.clamp_stack_count(stack.id, stack.count)
		if count <= 0 {
			continue
		}
		items << playerdb.InvItem{
			slot:             slot
			id:               stack.id
			meta:             stack.meta
			count:            count
			block_runtime_id: stack.block_runtime_id
			raw_extra_data:   stack.raw_extra_data.clone()
		}
	}
	current := s.player.movement()
	mut provider := s.hub.player_data_provider
	provider.save(s.player_key(), playerdb.PlayerData{
		x:              current.position.x
		y:              current.position.y
		z:              current.position.z
		yaw:            current.yaw
		pitch:          current.pitch
		gamemode:       s.player.game_mode()
		items:          items
		has_last_death: s.player.has_last_death()
		last_death_x:   s.player.last_death_pos().x
		last_death_y:   s.player.last_death_pos().y
		last_death_z:   s.player.last_death_pos().z
	}) or { s.log.warn('Failed to save player ${s.player_key()}: ${err}') }
}
