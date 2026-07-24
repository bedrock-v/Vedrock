module session

import os
import protocol
import protocol.types
import protocol.serializer
import server.conf
import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.player
import server.player.playerdb

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

fn test_save_data_preserves_inventory_slot_numbers() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_slot_save_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := new_hub(gamedata.GameData{})
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
	mut hub := new_hub(gamedata.GameData{})
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

fn test_player_data_uses_session_configured_players_dir() {
	dir_a := os.join_path(os.vtmp_dir(), 'vedrock_players_a_${os.getpid()}')
	dir_b := os.join_path(os.vtmp_dir(), 'vedrock_players_b_${os.getpid()}')
	defer {
		os.rmdir_all(dir_a) or {}
		os.rmdir_all(dir_b) or {}
	}
	mut hub := new_hub(gamedata.GameData{})
	mut sess_a := &NetworkSession{
		player: &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		hub:    hub
		cfg:    conf.Config{
			players_dir: dir_a
		}
		log:    logger.new(.info)
	}
	mut sess_b := &NetworkSession{
		player: &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		hub:    hub
		cfg:    conf.Config{
			players_dir: dir_b
		}
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
