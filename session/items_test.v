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

fn test_item_registry_roundtrip() {
	decoded := decode_packet(item_registry())!
	assert decoded.name() == 'ItemRegistryPacket'
	if decoded is protocol.ItemRegistryPacket {
		assert decoded.entries.len == item_catalog.len
		assert decoded.entries[0].string_id == 'minecraft:stone'
		assert decoded.entries[0].numeric_id == 1
	} else {
		assert false
	}
}

fn test_creative_content_roundtrip() {
	decoded := decode_packet(creative_content())!
	assert decoded.name() == 'CreativeContentPacket'
	if decoded is protocol.CreativeContentPacket {
		assert decoded.groups.len == 1
		assert decoded.items.len == item_catalog.len
	} else {
		assert false
	}
}

fn test_starter_inventory_roundtrip() {
	decoded := decode_packet(starter_inventory())!
	assert decoded.name() == 'InventoryContentPacket'
	if decoded is protocol.InventoryContentPacket {
		assert decoded.window_id == inventory_window_id
		assert decoded.items.len == inventory_slot_count
		assert decoded.items[0].item_stack.id == 1
		assert decoded.items[0].item_stack.count == 64
		assert decoded.items[0].item_stack.block_runtime_id == world_stone_id()
	} else {
		assert false
	}
}

fn world_stone_id() int {
	return item_catalog[0].block_network_id
}

fn test_set_actor_data_flags_roundtrip() {
	flags := entity_flag_bit(entity_flag_affected_by_gravity) | entity_flag_bit(entity_flag_has_collision)
	decoded := decode_packet(&protocol.SetActorDataPacket{
		actor_runtime_id: 1
		metadata:         [
			types.MetadataEntry{
				key:   meta_key_flags
				value: types.MetaLong{
					value: flags
				}
			},
		]
	})!
	assert decoded.name() == 'SetActorDataPacket'
	if decoded is protocol.SetActorDataPacket {
		assert decoded.metadata.len == 1
		assert decoded.metadata[0].key == meta_key_flags
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
