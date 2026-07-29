module session

import os
import protocol
import protocol.version.v662.packets as packets_662
import protocol.version.v662.types as types_662
import protocol.version.v729.packets as packets_729
import protocol.version.v944.packets as packets_944
import protocol.version.v944.types as types_944
import protocol.version.v1001.packets as packets_1001
import types
import protocol.serializer
import server.conf
import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.internal.network
import server.player
import server.player.playerdb

fn decode_packet(p protocol.Packet) !protocol.Packet {
	mut pool := network.new_selected_packet_pool()
	encoded := protocol.encode_packet_to_bytes(p)
	mut r := serializer.new_reader(encoded)
	return pool.decode(mut r)!
}

fn test_inventory_content_roundtrip() {
	decoded := decode_packet(&packets_1001.InventoryContentPacket{
		inventory_id:        u32(inventory_window_id)
		slots:               [
			network.item_descriptor_v975(types.ItemStack{ id: 1, count: 64 }),
		]
		container_name_data: types_944.FullContainerName{
			container: .inventory_container
		}
		storage_item:        network.item_descriptor_v975(types.ItemStack{})
	})!
	assert decoded.name() == 'InventoryContentPacket'
	if decoded is packets_1001.InventoryContentPacket {
		assert decoded.inventory_id == u32(inventory_window_id)
		assert decoded.slots[0].id == 1
	} else {
		assert false
	}
}

fn test_container_open_roundtrip() {
	decoded := decode_packet(&packets_944.ContainerOpenPacket{
		container_id:    .inventory
		container_type:  .inventory
		position:        types_944.NetworkBlockPosition{
			x: 0
			y: 64
			z: 0
		}
		target_actor_id: network.actor_unique_id(-1)
	})!
	assert decoded.name() == 'ContainerOpenPacket'
	if decoded is packets_944.ContainerOpenPacket {
		assert decoded.container_id == .inventory
		assert decoded.target_actor_id.value == -1
	} else {
		assert false
	}
}

fn test_set_actor_data_flags_roundtrip() {
	flags := entity_flag_bit(network.entity_flag_affected_by_gravity) | entity_flag_bit(network.entity_flag_has_collision)
	decoded := decode_packet(&packets_662.SetActorDataPacket{
		target_runtime_id: network.actor_runtime_id(1)
		actor_data:        [
			types_662.DataItem{
				data_item_id:   network.meta_key_flags
				data_item_type: types_662.DataItemType(types_662.DataItemInt64{
					value: flags
				})
			},
		]
		synced_properties: types_662.PropertySyncData{}
		tick:              0
	})!
	assert decoded.name() == 'SetActorDataPacket'
	if decoded is packets_662.SetActorDataPacket {
		assert decoded.actor_data.len == 1
		assert decoded.actor_data[0].data_item_id == network.meta_key_flags
	} else {
		assert false
	}
}

fn test_update_attributes_roundtrip() {
	decoded := decode_packet(&packets_729.UpdateAttributesPacket{
		target_runtime_id:       network.actor_runtime_id(4)
		attribute_list:          [
			player_attribute('minecraft:health', 0.0, 20.0, 20.0),
			player_attribute('minecraft:movement', 0.0, 1.0, 0.1),
		]
		ticks_since_sim_started: 0
	})!
	assert decoded.name() == 'UpdateAttributesPacket'
	if decoded is packets_729.UpdateAttributesPacket {
		assert decoded.attribute_list.len == 2
		assert decoded.attribute_list[0].attribute_name == 'minecraft:health'
		assert decoded.attribute_list[0].current_value == 20.0
	} else {
		assert false
	}
}

fn test_save_data_preserves_inventory_slot_numbers() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_slot_save_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := new_hub(gamedata.GameData{},
		player_data_provider: playerdb.FileProvider{
			dir: dir
		}
	)
	mut sess := &NetworkSession{
		player: &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		hub:    hub
		cfg:    conf.Config{
			players_dir: dir
		}
		log:    logger.new(.info)
	}
	stack := types.ItemStack{
		id:    5
		count: 3
	}
	net_id := sess.player.track_stack(stack)
	sess.player.set_slot(8, net_id)

	sess.save_player_data()
	loaded := playerdb.load_player(dir, 'Alex') or {
		assert false, 'load returned none'
		return
	}
	assert loaded.items.len == 1
	assert loaded.items[0].slot == 8

	mut restored := &NetworkSession{
		player: player.new_player()
		hub:    hub
		cfg:    conf.Config{
			players_dir: dir
		}
		log:    logger.new(.info)
	}
	restored.player.set_loaded_items(loaded.items)
	restored.restore_inventory()
	_, empty_net := restored.inventory_stack_at(0)
	slot_stack, slot_net := restored.inventory_stack_at(8)
	assert empty_net == 0
	assert slot_net != 0
	assert slot_stack.id == 5
	assert slot_stack.count == 3
}

fn test_save_data_preserves_inventory_extra_data() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_extra_data_save_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := new_hub(gamedata.GameData{},
		player_data_provider: playerdb.FileProvider{
			dir: dir
		}
	)
	extra := [u8(0x0a), 0x01, 0x02, 0x03]
	mut sess := &NetworkSession{
		player: &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		hub:    hub
		cfg:    conf.Config{
			players_dir: dir
		}
		log:    logger.new(.info)
	}
	stack := types.ItemStack{
		id:             5
		count:          1
		raw_extra_data: extra.clone()
	}
	net_id := sess.player.track_stack(stack)
	sess.player.set_slot(3, net_id)

	sess.save_player_data()
	loaded := playerdb.load_player(dir, 'Alex') or {
		assert false, 'load returned none'
		return
	}
	assert loaded.items.len == 1
	assert loaded.items[0].raw_extra_data == extra

	mut restored := &NetworkSession{
		player: player.new_player()
		hub:    hub
		cfg:    conf.Config{
			players_dir: dir
		}
		log:    logger.new(.info)
	}
	restored.player.set_loaded_items(loaded.items)
	restored.restore_inventory()
	slot_stack, slot_net := restored.inventory_stack_at(3)
	assert slot_net != 0
	assert slot_stack.raw_extra_data == extra
}

fn test_player_data_uses_the_owning_hubs_provider() {
	dir_a := os.join_path(os.vtmp_dir(), 'vedrock_players_a_${os.getpid()}')
	dir_b := os.join_path(os.vtmp_dir(), 'vedrock_players_b_${os.getpid()}')
	defer {
		os.rmdir_all(dir_a) or {}
		os.rmdir_all(dir_b) or {}
	}
	mut hub_a := new_hub(gamedata.GameData{},
		player_data_provider: playerdb.FileProvider{
			dir: dir_a
		}
	)
	mut hub_b := new_hub(gamedata.GameData{},
		player_data_provider: playerdb.FileProvider{
			dir: dir_b
		}
	)
	mut sess_a := &NetworkSession{
		player: &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		hub:    hub_a
		log:    logger.new(.info)
	}
	mut sess_b := &NetworkSession{
		player: &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		hub:    hub_b
		log:    logger.new(.info)
	}
	sess_a.player.reset_position(types.Vector3{1.0, 2.0, 3.0})
	sess_b.player.reset_position(types.Vector3{9.0, 8.0, 7.0})

	sess_a.save_player_data()
	sess_b.save_player_data()

	loaded_a := playerdb.load_player(dir_a, 'Alex') or {
		assert false, 'load A returned none'
		return
	}
	loaded_b := playerdb.load_player(dir_b, 'Alex') or {
		assert false, 'load B returned none'
		return
	}
	assert loaded_a.x == 1.0
	assert loaded_b.x == 9.0
}
