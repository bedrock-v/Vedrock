module session

import src as protocol
import src.serializer

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
