module session

import time
import bedrock_v.protocol.types
import server.internal.gamedata
import server.internal.logger
import server.player
import server.internal.auth
import server.world
import server.world.db
import bedrock_v.protocol.current as proto

fn mob_equipment_packet(runtime_id u64, stack types.ItemStackWrapper, slot int) proto.MobEquipmentPacket {
	return proto.MobEquipmentPacket{
		target_runtime_id: proto.actor_runtime_id(runtime_id)
		item:              proto.item_descriptor_v2(stack.item_stack)
		slot:              i8(slot)
		selected_slot:     i8(slot)
		container_id:      proto.ContainerID.inventory
	}
}

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

fn mob_equipment_test_session(mut hub Hub, mut wr WorldRuntime, name string, transport &FakeTransport) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: name
	}
	mut s := &NetworkSession{
		player:        pl
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		transport:     transport
		spawned:       true
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	hub.add(s)
	world_call[bool]('test', mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn test_handle_mob_equipment_selects_hotbar_slot() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := mob_equipment_test_session(mut hub, mut wr, 'Alex', &FakeTransport{})

	stack := types.ItemStackWrapper{
		item_stack: types.ItemStack{
			id:    123
			count: 1
		}
	}
	s.handle_mob_equipment(mob_equipment_packet(s.runtime_id, stack, 4)) or {
		panic('handle_mob_equipment failed: ${err}')
	}
	world_call[bool]('test', mut wr, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert s.player.held_slot() == 4
	assert s.player.held_item().item_stack.id == 123
}

// The equipment change broadcast must reach only observers in the same world.
fn test_mob_equipment_broadcast_isolated_to_owning_world() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut actor := mob_equipment_test_session(mut hub, mut wr_a, 'Alex', &FakeTransport{})
	mut transport_a := &FakeTransport{}
	mut observer_a := mob_equipment_test_session(mut hub, mut wr_a, 'Steve', transport_a)
	mut transport_b := &FakeTransport{}
	mut observer_b := mob_equipment_test_session(mut hub, mut wr_b, 'Bob', transport_b)

	stack := types.ItemStackWrapper{
		item_stack: types.ItemStack{
			id:    123
			count: 1
		}
	}
	actor.handle_mob_equipment(mob_equipment_packet(actor.runtime_id, stack, 4)) or {
		panic('handle_mob_equipment failed: ${err}')
	}
	world_call[bool]('test', mut wr_a, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }
	// The world_call barrier only proves the world actor finished
	// broadcasting; each observer's own outbound writer still has to drain
	// that delivery asynchronously afterward.
	assert wait_for_sent_len(transport_a, 1, 5000)

	mut a_saw_it := false
	for p in transport_a.sent {
		if p is proto.MobEquipmentPacket {
			a_saw_it = true
		}
	}
	mut b_saw_it := false
	for p in transport_b.sent {
		if p is proto.MobEquipmentPacket {
			b_saw_it = true
		}
	}
	assert a_saw_it
	assert !b_saw_it
}

fn test_mob_equipment_stale_epoch_produces_no_effect() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := mob_equipment_test_session(mut hub, mut wr_a, 'Alex', &FakeTransport{})

	stale_epoch := s.world_binding().epoch
	assert s.change_world('world-b', 0.0, 0.0, 0.0)

	task := PlayerMobEquipmentTask{
		runtime_id:  s.runtime_id
		epoch:       stale_epoch
		hotbar_slot: 4
		item:        types.ItemStackWrapper{
			item_stack: types.ItemStack{
				id:    123
				count: 1
			}
		}
	}
	assert wr_a.submit(task)
	world_call[bool]('test', mut wr_a, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert s.player.held_item().item_stack.id != 123
}

fn test_creative_stack_request_rejected_for_survival_player() {
	mut hub := new_hub(gamedata.GameData{
		creative_items: [
			gamedata.CreativeItem{
				numeric_id:       123
				block_runtime_id: 456
			},
		]
	})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := mob_equipment_test_session(mut hub, mut wr, 'Alex', &FakeTransport{})
	s.player.set_game_mode(.survival)
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	requests := [
		proto.RequestsEntry{
			client_request_id: 1
			actions:           [
				proto.ItemStackActionCraftCreative{
					creative_item_network_id:   1
					number_of_requested_crafts: 1
				},
				proto.ItemStackActionPlace{
					amount:      1
					source:      proto.ItemStackRequestSlotInfo{
						container_name: proto.FullContainerName{
							container: .inventory_container
						}
						slot:           0
						raw_id:         0
					}
					destination: proto.ItemStackRequestSlotInfo{
						container_name: proto.FullContainerName{
							container: .hotbar_container
						}
						slot:           0
						raw_id:         0
					}
				},
			]
		},
	]
	world_call[[]proto.ItemStackResponseInfo]('test', mut wr, fn [rid, epoch, requests] (mut tx WorldTx) []proto.ItemStackResponseInfo {
		return process_item_stack_requests(mut tx, rid, epoch, requests)
	}) or { []proto.ItemStackResponseInfo{} }

	_, net := s.inventory_stack_at(0)
	assert net == 0
	if _ := s.player.pending_creative() {
		assert false
	}
}

fn test_move_doesnt_merge_stacks_with_diff_metadata() {
	mut hub := new_hub(gamedata.GameData{})
	mut s := &NetworkSession{
		player: player.new_player()
		hub:    hub
		log:    logger.new(.info)
	}
	source := types.ItemStack{
		id:    5
		meta:  1
		count: 4
	}
	dest := types.ItemStack{
		id:    5
		meta:  2
		count: 8
	}
	source_net := s.player.track_stack(source)
	dest_net := s.player.track_stack(dest)
	s.player.set_slot(0, source_net)
	s.player.set_slot(1, dest_net)

	changes := s.apply_move(proto.ItemStackRequestSlotInfo{
		container_name: proto.FullContainerName{
			container: .hotbar_container
		}
		slot:           0
		raw_id:         source_net
	}, proto.ItemStackRequestSlotInfo{
		container_name: proto.FullContainerName{
			container: .hotbar_container
		}
		slot:           1
		raw_id:         dest_net
	}, 2)

	assert changes.len == 0
	got_source, got_source_net := s.inventory_stack_at(0)
	got_dest, got_dest_net := s.inventory_stack_at(1)
	assert got_source_net == source_net
	assert got_source.meta == 1
	assert got_source.count == 4
	assert got_dest_net == dest_net
	assert got_dest.meta == 2
	assert got_dest.count == 8
}

fn test_requested_amount_never_exceeds_what_the_slot_holds() {
	assert requested_amount(2, 5) == 2
	assert requested_amount(0, 5) == 5
	assert requested_amount(9, 5) == 5
	// A negative wire amount would otherwise leave the source stack larger
	// than it started, duplicating items.
	assert requested_amount(-5, 5) == 5
}

fn test_flat_slot_rejects_a_slot_outside_the_inventory() {
	container := proto.FullContainerName{
		container: .inventory_container
	}
	assert flat_slot(container, 0)? == 0
	assert flat_slot(container, i8(inventory_slot_count - 1))? == inventory_slot_count - 1
	if _ := flat_slot(container, i8(inventory_slot_count)) {
		assert false, 'expected a slot past the inventory to be rejected'
	}
	if _ := flat_slot(container, -1) {
		assert false, 'expected a negative slot to be rejected'
	}
}
