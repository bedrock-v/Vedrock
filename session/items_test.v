module session

import protocol
import protocol.types
import protocol.serializer

fn decode_packet(p protocol.Packet) !protocol.Packet {
	mut pool := protocol.new_packet_pool()
	encoded := protocol.encode_packet_to_bytes(p)
	mut r := serializer.new_reader(encoded)
	return pool.decode(mut r)!
}

fn test_inventory_content_roundtrip() {
	decoded := decode_packet(&protocol.InventoryContentPacket{
		window_id:      inventory_window_id
		items:          [wrap_stack(types.ItemStack{ id: 1, count: 64 })]
		container_name: types.FullContainerName{
			container_id: 0
		}
		storage:        empty_stack()
	})!
	assert decoded.name() == 'InventoryContentPacket'
	if decoded is protocol.InventoryContentPacket {
		assert decoded.window_id == inventory_window_id
		assert decoded.items[0].item_stack.id == 1
	} else {
		assert false
	}
}

fn test_container_open_roundtrip() {
	decoded := decode_packet(&protocol.ContainerOpenPacket{
		window_id:       0
		window_type:     protocol.container_type_inventory
		block_position:  types.BlockPosition{0, 64, 0}
		actor_unique_id: -1
	})!
	assert decoded.name() == 'ContainerOpenPacket'
	if decoded is protocol.ContainerOpenPacket {
		assert decoded.window_id == 0
		assert decoded.actor_unique_id == -1
	} else {
		assert false
	}
}

fn test_set_actor_data_flags_roundtrip() {
	flags := entity_flag_bit(protocol.entity_flag_affected_by_gravity) | entity_flag_bit(protocol.entity_flag_has_collision)
	decoded := decode_packet(&protocol.SetActorDataPacket{
		actor_runtime_id: 1
		metadata:         [
			types.MetadataEntry{
				key:   protocol.meta_key_flags
				value: types.MetaLong{
					value: flags
				}
			},
		]
	})!
	assert decoded.name() == 'SetActorDataPacket'
	if decoded is protocol.SetActorDataPacket {
		assert decoded.metadata.len == 1
		assert decoded.metadata[0].key == protocol.meta_key_flags
	} else {
		assert false
	}
}

fn test_update_attributes_roundtrip() {
	decoded := decode_packet(&protocol.UpdateAttributesPacket{
		actor_runtime_id: 4
		entries:          [
			player_attribute('minecraft:health', 0.0, 20.0, 20.0),
			player_attribute('minecraft:movement', 0.0, 1.0, 0.1),
		]
		tick:             0
	})!
	assert decoded.name() == 'UpdateAttributesPacket'
	if decoded is protocol.UpdateAttributesPacket {
		assert decoded.entries.len == 2
		assert decoded.entries[0].id == 'minecraft:health'
		assert decoded.entries[0].current == 20.0
	} else {
		assert false
	}
}
