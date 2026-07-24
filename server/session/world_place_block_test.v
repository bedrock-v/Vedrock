module session

import time
import protocol
import protocol.types
import server.event
import server.internal.gamedata
import server.player
import server.internal.auth
import server.world
import server.world.db
import server.item

fn wait_for_sent_len(transport &FakeTransport, want int, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for transport.sent.len < want {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return transport.sent.len >= want
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return transport.sent.len >= want
		}
	}
	return true
}

fn place_test_data() gamedata.GameData {
	return gamedata.GameData{
		item_id_by_name: {
			'minecraft:test_block': 500
			'minecraft:test_sign':  501
		}
	}
}

fn place_test_hub() &Hub {
	mut hub := new_hub(place_test_data())
	hub.items.register(item.BlockItem{
		id:            'minecraft:test_block'
		block_runtime: world.bedrock.network_id
	})
	sign_id :=
		hub.blocks.get_by_name('minecraft:standing_sign') or { panic('missing sign') }.runtime_id()
	hub.items.register(item.BlockItem{
		id:            'minecraft:test_sign'
		block_runtime: sign_id
	})
	return hub
}

fn place_test_session(mut hub Hub, mut transport FakeTransport, mut wr WorldRuntime) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	pl.set_game_mode(protocol.game_type_survival)
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		transport:     transport
		hub:           hub
		world_runtime: wr
		world:         wr.world
		generator:     world.VoidGenerator{}
	}
	s.player.reset_position(types.Vector3{0.5, 1.62, 0.5})
	hub.add(s)
	// PlayerPlaceBlockTask requires world membership.
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn give_held_stack(mut s NetworkSession, item_id int, count int) {
	stack := types.ItemStack{
		id:    item_id
		count: count
	}
	net_id := s.player.track_stack(stack)
	s.player.set_slot(s.player.held_slot(), net_id)
	s.player.set_held(s.player.held_slot(), wrap_stack_id(stack, net_id))
}

fn place_click_packet(clicked_pos types.BlockPosition, click_pos types.Vector3, held_id int) protocol.InventoryTransactionPacket {
	return protocol.InventoryTransactionPacket{
		transaction_type: protocol.inventory_transaction_type_use_item
		use_item:         protocol.UseItemTransactionData{
			action_type:       protocol.item_use_action_click_block
			trigger_type:      1
			block_position:    clicked_pos
			block_face:        1
			hotbar_slot:       0
			held_item:         types.ItemStackWrapper{
				item_stack: types.ItemStack{
					id:               held_id
					count:            64
					block_runtime_id: 0
				}
			}
			position:          click_pos
			clicked_position:  types.Vector3{0.5, 1.0, 0.5}
			block_runtime_id:  u32(0)
			client_prediction: 1
		}
	}
}

fn test_place_block_writes_and_consumes_item_once() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	target.set_block(0, 0, 1, world.bedrock.network_id)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := place_test_session(mut hub, mut transport, mut wr)
	give_held_stack(mut s, 500, 3)
	defer {
		hub.close_worlds()
	}

	s.handle_inventory_transaction(place_click_packet(types.BlockPosition{0, 0, 1}, types.Vector3{0.5, 1.62, 0.5},
		500))!

	assert target.block_override(0, 1, 1) or { -1 } == world.bedrock.network_id
	stack, _ := s.inventory_stack_at(s.player.held_slot())
	assert stack.count == 2
}

struct CancelBlockPlaceHandler {
	event.NopHandler
}

fn (mut h CancelBlockPlaceHandler) on_block_place(mut ctx event.Context[event.BlockPlaceData]) {
	ctx.cancel()
}

fn test_place_block_cancelled_leaves_block_and_item_unchanged() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	target.set_block(0, 0, 1, world.bedrock.network_id)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	// block_place is dispatched on the owning world's own event bus, not
	// Hub's global one.
	wr.events.register(&CancelBlockPlaceHandler{}, .normal)
	mut transport := &FakeTransport{}
	mut s := place_test_session(mut hub, mut transport, mut wr)
	give_held_stack(mut s, 500, 3)
	defer {
		hub.close_worlds()
	}

	s.handle_inventory_transaction(place_click_packet(types.BlockPosition{0, 0, 1}, types.Vector3{0.5, 1.62, 0.5},
		500))!

	assert target.block_override(0, 1, 1) == none
	stack, _ := s.inventory_stack_at(s.player.held_slot())
	assert stack.count == 3
}

fn test_place_block_observer_in_another_world_receives_no_packet() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	hub.set_default_world('world')
	target.set_block(0, 0, 1, world.bedrock.network_id)
	other_world := db.new_world('other', none, 'void', world.overworld)
	hub.add_world(other_world)
	mut other_wr := hub.world_runtime('other') or { panic('expected other world runtime') }
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut placer_transport := &FakeTransport{}
	mut placer := place_test_session(mut hub, mut placer_transport, mut wr)
	give_held_stack(mut placer, 500, 1)

	mut observer_transport := &FakeTransport{}
	mut observer := place_test_session(mut hub, mut observer_transport, mut other_wr)

	placer.handle_inventory_transaction(place_click_packet(types.BlockPosition{0, 0, 1}, types.Vector3{0.5, 1.62, 0.5},
		500))!

	assert target.block_override(0, 1, 1) or { -1 } == world.bedrock.network_id
	for p in observer_transport.sent {
		assert p !is protocol.UpdateBlockPacket
	}
}

fn test_place_block_ignores_player_in_another_world_for_obstruction() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	target.set_block(0, 0, 1, world.bedrock.network_id)
	other_world := db.new_world('other', none, 'void', world.overworld)
	hub.add_world(other_world)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut other_wr := hub.world_runtime('other') or { panic('expected other world runtime') }
	defer {
		hub.close_worlds()
	}

	mut placer_transport := &FakeTransport{}
	mut placer := place_test_session(mut hub, mut placer_transport, mut wr)
	give_held_stack(mut placer, 500, 1)

	mut blocker_transport := &FakeTransport{}
	mut blocker := place_test_session(mut hub, mut blocker_transport, mut other_wr)
	blocker.player.reset_position(types.Vector3{0.5, 1.0 + player_eye_height, 1.5})

	placer.handle_inventory_transaction(place_click_packet(types.BlockPosition{0, 0, 1}, types.Vector3{0.5, 1.62, 0.5},
		500))!

	assert target.block_override(0, 1, 1) or { -1 } == world.bedrock.network_id
	stack, _ := placer.inventory_stack_at(placer.player.held_slot())
	assert stack.count == 0
}

// CountingPlaceHandler records block_place events to prove world scoped event
// isolation, not just packet isolation.
struct CountingPlaceHandler {
	event.NopHandler
mut:
	hits int
}

fn (mut h CountingPlaceHandler) on_block_place(mut ctx event.Context[event.BlockPlaceData]) {
	h.hits++
}

// A handler registered on world B's event bus must never observe a placement
// that happened in world A and vice versa.
fn test_place_block_event_isolated_to_owning_world() {
	mut hub := place_test_hub()
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	hub.set_default_world('world-a')
	world_a.set_block(0, 0, 1, world.bedrock.network_id)
	world_b := db.new_world('world-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut handler_a := &CountingPlaceHandler{}
	mut handler_b := &CountingPlaceHandler{}
	wr_a.events.register(handler_a, .normal)
	wr_b.events.register(handler_b, .normal)

	mut transport := &FakeTransport{}
	mut s := place_test_session(mut hub, mut transport, mut wr_a)
	give_held_stack(mut s, 500, 1)

	s.handle_inventory_transaction(place_click_packet(types.BlockPosition{0, 0, 1}, types.Vector3{0.5, 1.62, 0.5},
		500))!

	assert handler_a.hits == 1
	assert handler_b.hits == 0
}

fn test_sign_tile_broadcasts_before_block_update() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	target.set_block(0, 0, 1, world.bedrock.network_id)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := place_test_session(mut hub, mut transport, mut wr)
	give_held_stack(mut s, 501, 1)
	defer {
		hub.close_worlds()
	}

	s.handle_inventory_transaction(place_click_packet(types.BlockPosition{0, 0, 1}, types.Vector3{0.5, 1.62, 0.5},
		501))!
	assert wait_for_sent_len(transport, 2, 5000)

	mut tile_index := -1
	mut block_index := -1
	for i, p in transport.sent {
		if tile_index == -1 && p is protocol.BlockActorDataPacket {
			tile_index = i
		}
		if block_index == -1 && p is protocol.UpdateBlockPacket {
			if p.block_position == types.BlockPosition{0, 1, 1} {
				block_index = i
			}
		}
	}
	assert tile_index != -1
	assert block_index != -1
	assert tile_index < block_index
	assert target.tile_text(0, 1, 1) or { 'missing' } == ''
}

fn test_handled_interaction_does_not_consume_or_place_held_item() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	sign_id :=
		hub.blocks.get_by_name('minecraft:standing_sign') or { panic('missing sign') }.runtime_id()
	target.set_block(0, 0, 1, sign_id)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := place_test_session(mut hub, mut transport, mut wr)
	give_held_stack(mut s, 500, 3)
	defer {
		hub.close_worlds()
	}

	s.handle_inventory_transaction(place_click_packet(types.BlockPosition{0, 0, 1}, types.Vector3{0.5, 1.62, 0.5},
		500))!
	assert wait_for_sent_len(transport, 1, 5000)

	mut opened_editor := false
	for p in transport.sent {
		if p is protocol.OpenSignPacket {
			opened_editor = true
		}
		assert p !is protocol.UpdateBlockPacket
	}
	assert opened_editor
	assert target.block_override(0, 1, 1) == none
	stack, _ := s.inventory_stack_at(s.player.held_slot())
	assert stack.count == 3
}

fn test_door_placement_upper_blocked_leaves_both_untouched() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := place_test_session(mut hub, mut transport, mut wr)
	s.player.reset_position(types.Vector3{10.5, 1.62, 10.5})
	defer {
		hub.close_worlds()
	}

	mut blocker_transport := &FakeTransport{}
	mut blocker := place_test_session(mut hub, mut blocker_transport, mut wr)
	blocker.player.reset_position(types.Vector3{0.5, 1.0 + player_eye_height, 0.5})

	mut tx := &WorldTx{
		wr: wr
	}
	pos := types.BlockPosition{0, 0, 0}
	above := types.BlockPosition{0, 1, 0}
	parts := world.DoorPlacement{
		lower: 1001
		upper: 1002
	}
	placed := tx.place_door_pair(mut s, pos, parts)
	assert !placed
	assert target.block_override(pos.x, pos.y, pos.z) == none
	assert target.block_override(above.x, above.y, above.z) == none
}

fn test_door_placement_cancelled_leaves_both_untouched() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	// block_place is dispatched on the owning world's own event bus, not
	// Hub's global one.
	wr.events.register(&CancelBlockPlaceHandler{}, .normal)
	mut transport := &FakeTransport{}
	mut s := place_test_session(mut hub, mut transport, mut wr)
	s.player.reset_position(types.Vector3{10.5, 1.62, 10.5})
	defer {
		hub.close_worlds()
	}

	mut tx := &WorldTx{
		wr: wr
	}
	pos := types.BlockPosition{0, 0, 0}
	above := types.BlockPosition{0, 1, 0}
	parts := world.DoorPlacement{
		lower: 1001
		upper: 1002
	}
	placed := tx.place_door_pair(mut s, pos, parts)
	assert !placed
	assert target.block_override(pos.x, pos.y, pos.z) == none
	assert target.block_override(above.x, above.y, above.z) == none
}

fn test_door_placement_writes_both_halves_atomically_in_same_world() {
	mut hub := place_test_hub()
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := place_test_session(mut hub, mut transport, mut wr)
	s.player.reset_position(types.Vector3{10.5, 1.62, 10.5})
	defer {
		hub.close_worlds()
	}

	mut tx := &WorldTx{
		wr: wr
	}
	pos := types.BlockPosition{0, 0, 0}
	above := types.BlockPosition{0, 1, 0}
	parts := world.DoorPlacement{
		lower: 1001
		upper: 1002
	}
	placed := tx.place_door_pair(mut s, pos, parts)
	assert placed
	assert target.block_override(pos.x, pos.y, pos.z) or { -1 } == 1001
	assert target.block_override(above.x, above.y, above.z) or { -1 } == 1002
}
