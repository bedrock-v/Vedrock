module session

import protocol
import protocol.types
import server.event
import server.internal.gamedata
import server.internal.auth
import server.world
import server.world.db
import server.block
import server.item

fn test_within_place_reach_survival_vs_creative() {
	mut s := &NetworkSession{
		position:  types.Vector3{0.0, player_eye_height, 0.0}
		game_mode: protocol.game_type_survival
	}
	// near/far avoided as names: legacy Windows headers define them as macros.
	near_pos := types.BlockPosition{0, 5, 0}
	// Beyond survival's reach but within creative's reach.
	far_pos := types.BlockPosition{10, 0, 0}
	assert s.within_place_reach(near_pos)
	assert !s.within_place_reach(far_pos)

	s.game_mode = protocol.game_type_creative
	assert s.within_place_reach(far_pos)
}

fn test_place_block_rejects_when_occupied() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		position:   types.Vector3{0.0, player_eye_height, 0.0}
		generator:  world.FlatGenerator{}
	}
	hub.add(s)

	// FlatGenerator's bottom layer (bedrock) sits at the dimension's min_y.
	pos := types.BlockPosition{0, world.overworld.min_y, 0}
	placed := s.place_block(pos, world.bedrock.network_id)!
	assert !placed
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.UpdateBlockPacket {
		assert sent.block_position == pos
	} else {
		assert false
	}
}

fn test_place_block_writes_and_broadcasts_when_clear() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', unsafe { nil }, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		position:   types.Vector3{0.0, player_eye_height, 0.0}
		generator:  world.VoidGenerator{}
	}
	hub.add(s)

	pos := types.BlockPosition{5, 5, 5}
	placed := s.place_block(pos, world.bedrock.network_id)!
	assert placed

	// write_block_runtime blocks until the WorldJob actually lands (see its
	// comment). No need to run the job manually or poll for it here.
	assert target.block_override(pos.x, pos.y, pos.z) or { -1 } == world.bedrock.network_id

	mut saw_update := false
	for p in transport.sent {
		if p is protocol.UpdateBlockPacket {
			if p.block_position == pos && p.block_runtime_id == world.bedrock.network_id {
				saw_update = true
			}
		}
	}
	assert saw_update
}

fn test_place_block_cancelled_resends_skips_write() {
	mut hub := new_hub(gamedata.GameData{})
	hub.events.register(&CancelBlockPlaceHandler{}, .normal)
	target := db.new_world('world', unsafe { nil }, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		position:   types.Vector3{0.0, player_eye_height, 0.0}
		generator:  world.VoidGenerator{}
	}
	hub.add(s)

	pos := types.BlockPosition{5, 5, 5}
	placed := s.place_block(pos, world.bedrock.network_id)!
	assert !placed
	if _ := target.block_override(pos.x, pos.y, pos.z) {
		assert false
	}
	assert transport.sent.len == 1
}

struct CancelBlockPlaceHandler {
	event.NopHandler
}

fn (mut h CancelBlockPlaceHandler) on_block_place(mut ctx event.Context[event.BlockPlaceData]) {
	ctx.cancel()
}

fn test_break_block_unbreakable_resends_without_event() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		game_mode:  protocol.game_type_survival
		generator:  world.FlatGenerator{}
	}
	hub.add(s)

	pos := types.BlockPosition{0, world.overworld.min_y, 0}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	assert old_id != world.air.network_id
	s.break_block(pos)!
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.UpdateBlockPacket {
		assert sent.block_runtime_id == old_id
	} else {
		assert false
	}
}

fn test_break_block_air_is_noop() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		generator:  world.VoidGenerator{}
	}
	hub.add(s)

	s.break_block(types.BlockPosition{0, 0, 0})!
	assert transport.sent.len == 0
}

fn test_break_block_cancelled_resends_keeps_block() {
	mut hub := new_hub(gamedata.GameData{})
	hub.events.register(&CancelBlockBreakHandler{}, .normal)
	target := db.new_world('world', unsafe { nil }, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		game_mode:  protocol.game_type_survival
		generator:  world.FlatGenerator{}
	}
	hub.add(s)

	pos := types.BlockPosition{0, world.overworld.min_y, 0}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	s.break_block(pos)!
	if _ := target.block_override(pos.x, pos.y, pos.z) {
		assert false
	}
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.UpdateBlockPacket {
		assert sent.block_runtime_id == old_id
	} else {
		assert false
	}
}

struct CancelBlockBreakHandler {
	event.NopHandler
}

fn (mut h CancelBlockBreakHandler) on_block_break(mut ctx event.Context[event.BlockBreakData]) {
	ctx.cancel()
}

fn test_obstructed_by_entity_ignores_only_own_body() {
	mut hub := new_hub(gamedata.GameData{})
	mut alex := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		hub:        hub
		position:   types.Vector3{0.5, player_eye_height, 0.5}
	}
	hub.add(alex)

	// Alex's own body occupies (0,0,0), obstructed but self_only.
	obstructed, self_only := alex.obstructed_by_entity(types.BlockPosition{0, 0, 0})
	assert obstructed
	assert self_only

	// Nobody else occupies a faraway cell.
	clear_obstructed, clear_self_only := alex.obstructed_by_entity(types.BlockPosition{50, 0, 50})
	assert !clear_obstructed
	assert clear_self_only
}

fn test_obstructed_by_entity_blocks_other_player() {
	mut hub := new_hub(gamedata.GameData{})
	mut alex := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		hub:        hub
		position:   types.Vector3{10.5, player_eye_height, 10.5}
	}
	mut steve := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Steve'
		}
		runtime_id: 2
		hub:        hub
		position:   types.Vector3{0.5, player_eye_height, 0.5}
	}
	hub.add(alex)
	hub.add(steve)

	obstructed, self_only := alex.obstructed_by_entity(types.BlockPosition{0, 0, 0})
	assert obstructed
	assert !self_only
}

fn test_face_offset_covers_all_six_faces() {
	pos := types.BlockPosition{5, 5, 5}
	assert face_offset(pos, 0) == types.BlockPosition{5, 4, 5}
	assert face_offset(pos, 1) == types.BlockPosition{5, 6, 5}
	assert face_offset(pos, 2) == types.BlockPosition{5, 5, 4}
	assert face_offset(pos, 3) == types.BlockPosition{5, 5, 6}
	assert face_offset(pos, 4) == types.BlockPosition{4, 5, 5}
	assert face_offset(pos, 5) == types.BlockPosition{6, 5, 5}
}

fn test_required_break_ticks_formula() {
	assert required_break_ticks(0.0, 1.0) == 0
	assert required_break_ticks(0.5, 1.0) == 15
	assert required_break_ticks(1.5, 2.0) == 23
}

fn dirt_break_test_session(mut hub Hub, mut transport FakeTransport) &NetworkSession {
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		game_mode:  protocol.game_type_survival
		generator:  world.FlatGenerator{}
	}
	hub.add(s)
	return s
}

fn test_break_block_rejects_before_ticks_elapsed() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := dirt_break_test_session(mut hub, mut transport)

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0} // dirt layer
	dirt_id := s.block_at(pos.x, pos.y, pos.z)
	s.breaking = BreakProgress{pos.x, pos.y, pos.z, dirt_id, 0}
	hub.current_tick = 0

	s.break_block(pos)!
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.UpdateBlockPacket {
		assert sent.block_runtime_id == dirt_id
	} else {
		assert false
	}
}

fn test_break_block_succeeds_after_ticks_elapsed() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', unsafe { nil }, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := dirt_break_test_session(mut hub, mut transport)
	s.world = target

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := s.block_at(pos.x, pos.y, pos.z)
	s.breaking = BreakProgress{pos.x, pos.y, pos.z, dirt_id, 0}
	hub.current_tick = 20

	s.break_block(pos)!

	assert target.block_override(pos.x, pos.y, pos.z) or { -1 } == world.air.network_id
}

fn test_break_block_rejects_mismatched_position() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := dirt_break_test_session(mut hub, mut transport)

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	other_pos := types.BlockPosition{5, world.overworld.min_y + 1, 5}
	dirt_id := s.block_at(pos.x, pos.y, pos.z)
	s.breaking = BreakProgress{other_pos.x, other_pos.y, other_pos.z, dirt_id, 0}
	hub.current_tick = 100

	s.break_block(pos)!
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.UpdateBlockPacket {
		assert sent.block_runtime_id == dirt_id
	} else {
		assert false
	}
}

fn test_break_block_creative_bypasses_gating() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', unsafe { nil }, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		game_mode:  protocol.game_type_creative
		generator:  world.FlatGenerator{}
	}
	hub.add(s)

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	hub.current_tick = 0

	s.break_block(pos)!

	assert target.block_override(pos.x, pos.y, pos.z) or { -1 } == world.air.network_id
}

fn test_place_resolves_block_from_item_registry() {
	data := gamedata.GameData{
		item_id_by_name: {
			'minecraft:oak_sign': 390
		}
	}
	mut hub := new_hub(data)
	target := db.new_world('world', unsafe { nil }, 'flat', world.overworld)
	hub.add_world(target)
	sign_id :=
		hub.blocks.get_by_name('minecraft:standing_sign') or { panic('missing sign') }.runtime_id()
	hub.items.register(item.BlockItem{
		id:            'minecraft:oak_sign'
		block_runtime: sign_id
	})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		game_mode:  protocol.game_type_creative
		position:   types.Vector3{2.1901546, -58.37999, 10.302694}
		generator:  world.FlatGenerator{}
	}
	hub.add(s)

	place_packet := protocol.InventoryTransactionPacket{
		transaction_type: protocol.inventory_transaction_type_use_item
		use_item:         protocol.UseItemTransactionData{
			action_type:       protocol.item_use_action_click_block
			trigger_type:      1
			block_position:    types.BlockPosition{2, -61, 12}
			block_face:        1
			hotbar_slot:       0
			held_item:         types.ItemStackWrapper{
				item_stack: types.ItemStack{
					id:               390
					count:            16
					block_runtime_id: 0
				}
			}
			position:          types.Vector3{2.1901546, -58.37999, 10.302694}
			clicked_position:  types.Vector3{0.35214186, 1.0, 0.20941257}
			block_runtime_id:  u32(3727763636) // grass_block echo: must NOT BE USED
			client_prediction: 1
		}
	}

	s.handle_inventory_transaction(place_packet)!

	target_id := s.block_at(2, -60, 12)
	got := hub.blocks.get(target_id) or { panic('placed block not in registry') }
	assert got is block.SignBlock
	assert got.identifier() == 'minecraft:standing_sign'
}

fn test_empty_hand_interact_places_nothing() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', unsafe { nil }, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		game_mode:  protocol.game_type_creative
		position:   types.Vector3{2.1901546, -58.37999, 10.302694}
		generator:  world.FlatGenerator{}
	}
	hub.add(s)

	interact_packet := protocol.InventoryTransactionPacket{
		transaction_type: protocol.inventory_transaction_type_use_item
		use_item:         protocol.UseItemTransactionData{
			action_type:       protocol.item_use_action_click_block
			trigger_type:      1
			block_position:    types.BlockPosition{2, -60, 12}
			block_face:        2
			hotbar_slot:       3
			held_item:         types.ItemStackWrapper{
				item_stack: types.ItemStack{
					id:               0
					count:            0
					block_runtime_id: 0
				}
			}
			position:          types.Vector3{2.1901546, -58.37999, 10.302694}
			clicked_position:  types.Vector3{0.42559528, 0.7279053, 0.25}
			block_runtime_id:  u32(2761757297) // nonzero even with empty hand
			client_prediction: 1
		}
	}
	s.handle_inventory_transaction(interact_packet)!

	assert s.block_at(2, -60, 12) == world.air.network_id
	assert s.block_at(2, -60, 11) == world.air.network_id
}

struct CancelItemConsumeHandler {
	event.NopHandler
}

fn (mut h CancelItemConsumeHandler) on_item_consume(mut ctx event.Context[event.ItemConsumeData]) {
	ctx.cancel()
}

fn test_cancelled_consume_keeps_stack() {
	mut hub := new_hub(gamedata.GameData{})
	hub.events.register(&CancelItemConsumeHandler{}, .normal)
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		hub:        hub
	}
	hub.add(s)
	stack := types.ItemStack{
		id:    300
		count: 1
	}
	net_id := s.track_stack(stack)
	s.inv_slots[s.held_slot] = net_id

	s.consume_held_item()

	got, got_net := s.inventory_stack_at(s.held_slot)
	assert got_net == net_id
	assert got.count == 1
}

fn drop_actions(slot int, old types.ItemStack, new_stack types.ItemStack, dropped types.ItemStack) []protocol.InventoryAction {
	return [
		protocol.InventoryAction{
			source_type: protocol.inventory_action_source_world
			new_item:    types.ItemStackWrapper{
				item_stack: dropped
			}
		},
		protocol.InventoryAction{
			source_type:    protocol.inventory_action_source_container
			window_id:      i8(inventory_window_id)
			inventory_slot: u32(slot)
			old_item:       types.ItemStackWrapper{
				item_stack: old
			}
			new_item:       types.ItemStackWrapper{
				item_stack: new_stack
			}
		},
	]
}

fn test_normal_transaction_drops_from_matching_slot() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		runtime_id: 1
		transport:  transport
		hub:        hub
	}
	hub.add(s)
	stack := types.ItemStack{
		id:    5
		count: 3
	}
	net := s.track_stack(stack)
	s.inv_slots[0] = net
	mut remaining := stack
	remaining.count = 2
	dropped := types.ItemStack{
		id:    5
		count: 1
	}

	s.handle_normal_transaction(drop_actions(0, stack, remaining, dropped))

	got, _ := s.inventory_stack_at(0)
	assert got.count == 2
	assert hub.entities.count() == 1
}

fn test_normal_transaction_rejects_world_action_without_source_slot() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		runtime_id: 1
		transport:  transport
		hub:        hub
	}
	hub.add(s)

	s.handle_normal_transaction([
		protocol.InventoryAction{
			source_type: protocol.inventory_action_source_world
			new_item:    types.ItemStackWrapper{
				item_stack: types.ItemStack{
					id:    276
					count: 64
				}
			}
		},
	])

	assert hub.entities.count() == 0
}

fn test_normal_transaction_rejects_mismatched_old_item() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		runtime_id: 1
		transport:  transport
		hub:        hub
	}
	hub.add(s)
	stack := types.ItemStack{
		id:    5
		count: 3
	}
	net := s.track_stack(stack)
	s.inv_slots[0] = net
	claimed := types.ItemStack{
		id:    5
		count: 64
	}
	dropped := types.ItemStack{
		id:    5
		count: 64
	}

	s.handle_normal_transaction(drop_actions(0, claimed, types.ItemStack{}, dropped))

	got, got_net := s.inventory_stack_at(0)
	assert got_net == net
	assert got.count == 3
	assert hub.entities.count() == 0
}

fn test_normal_transaction_rejects_drop_count_mismatch() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		runtime_id: 1
		transport:  transport
		hub:        hub
	}
	hub.add(s)
	stack := types.ItemStack{
		id:    5
		count: 3
	}
	net := s.track_stack(stack)
	s.inv_slots[0] = net
	mut remaining := stack
	remaining.count = 2
	dropped := types.ItemStack{
		id:    7
		count: 1
	}

	s.handle_normal_transaction(drop_actions(0, stack, remaining, dropped))

	got, got_net := s.inventory_stack_at(0)
	assert got_net == net
	assert got.count == 3
	assert hub.entities.count() == 0
}

fn test_normal_transaction_rejects_duplicated_actions() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		runtime_id: 1
		transport:  transport
		hub:        hub
	}
	hub.add(s)
	stack := types.ItemStack{
		id:    5
		count: 3
	}
	net := s.track_stack(stack)
	s.inv_slots[0] = net
	mut remaining := stack
	remaining.count = 2
	dropped := types.ItemStack{
		id:    5
		count: 1
	}
	mut actions := drop_actions(0, stack, remaining, dropped)
	actions << drop_actions(0, stack, remaining, dropped)

	s.handle_normal_transaction(actions)

	got, got_net := s.inventory_stack_at(0)
	assert got_net == net
	assert got.count == 3
	assert hub.entities.count() == 0
}

fn test_normal_transaction_rejects_world_action_with_nonzero_slot() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		runtime_id: 1
		transport:  transport
		hub:        hub
	}
	hub.add(s)
	stack := types.ItemStack{
		id:    5
		count: 3
	}
	net := s.track_stack(stack)
	s.inv_slots[0] = net
	mut remaining := stack
	remaining.count = 2
	dropped := types.ItemStack{
		id:    5
		count: 1
	}
	mut actions := drop_actions(0, stack, remaining, dropped)
	actions[0].inventory_slot = 1

	s.handle_normal_transaction(actions)

	got, got_net := s.inventory_stack_at(0)
	assert got_net == net
	assert got.count == 3
	assert hub.entities.count() == 0
}
