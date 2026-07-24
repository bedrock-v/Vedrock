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
import server.block
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

fn make_test_player(name string, mode int) &player.Player {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: name
	}
	pl.set_game_mode(mode)
	return pl
}

fn test_within_place_reach_survival_vs_creative() {
	mut pl := player.new_player()
	pl.set_game_mode(protocol.game_type_survival)
	mut s := &NetworkSession{
		player: pl
	}
	s.player.reset_position(types.Vector3{0.0, player_eye_height, 0.0})
	near := types.BlockPosition{0, 5, 0}
	// Beyond survival's reach but within creative's reach.
	far := types.BlockPosition{10, 0, 0}
	assert s.within_place_reach(near)
	assert !s.within_place_reach(far)

	s.player.set_game_mode(protocol.game_type_creative)
	assert s.within_place_reach(far)
}

fn test_place_block_rejects_when_occupied() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		generator:  world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{0.0, player_eye_height, 0.0})
	hub.add(s)

	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut tx := &WorldTx{
		wr: wr
	}

	// FlatGenerator's bottom layer (bedrock) sits at the dimension's min_y.
	pos := types.BlockPosition{0, world.overworld.min_y, 0}
	placed := tx.place_block_form(mut s, pos, world.bedrock.network_id)
	assert !placed
	assert wait_for_sent_len(transport, 1, 5000)
	sent := transport.sent[0]
	if sent is protocol.UpdateBlockPacket {
		assert sent.block_position == pos
	} else {
		assert false
	}
}

fn test_place_block_writes_and_broadcasts_when_clear() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		generator:  world.VoidGenerator{}
	}
	s.player.reset_position(types.Vector3{0.0, player_eye_height, 0.0})
	hub.add(s)

	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut tx := &WorldTx{
		wr: wr
	}
	tx.register_player(s)

	pos := types.BlockPosition{5, 5, 5}
	placed := tx.place_block_form(mut s, pos, world.bedrock.network_id)
	assert placed
	assert target.block_override(pos.x, pos.y, pos.z) or { -1 } == world.bedrock.network_id
	assert wait_for_sent_len(transport, 1, 5000)

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
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		generator:  world.VoidGenerator{}
	}
	s.player.reset_position(types.Vector3{0.0, player_eye_height, 0.0})
	hub.add(s)

	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	wr.events.register(&CancelBlockPlaceHandler{}, .normal)
	mut tx := &WorldTx{
		wr: wr
	}

	pos := types.BlockPosition{5, 5, 5}
	placed := tx.place_block_form(mut s, pos, world.bedrock.network_id)
	assert !placed
	if _ := target.block_override(pos.x, pos.y, pos.z) {
		assert false
	}
	assert wait_for_sent_len(transport, 1, 5000)
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
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	pl.set_game_mode(protocol.game_type_survival)
	mut s := &NetworkSession{
		player:     pl
		runtime_id: 1
		transport:  transport
		hub:        hub
		generator:  world.FlatGenerator{}
	}
	hub.add(s)

	pos := types.BlockPosition{0, world.overworld.min_y, 0}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	assert old_id != world.air.network_id
	s.break_block(pos)!
	assert wait_for_sent_len(transport, 1, 5000)
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
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
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

fn test_break_block_rejects_out_of_reach() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:     make_test_player('Alex', protocol.game_type_survival)
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		generator:  world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{0.0, player_eye_height, 0.0})
	hub.add(s)

	far := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	s.break_block(far)!
	assert target.block_override(far.x, far.y, far.z) or { -1 } == -1
}

fn test_break_block_cancelled_resends_keeps_block() {
	mut hub := new_hub(gamedata.GameData{})
	hub.events.register(&CancelBlockBreakHandler{}, .normal)
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:     make_test_player('Alex', protocol.game_type_survival)
		runtime_id: 1
		transport:  transport
		hub:        hub
		world:      target
		generator:  world.FlatGenerator{}
	}
	hub.add(s)

	pos := types.BlockPosition{0, world.overworld.min_y, 0}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	s.break_block(pos)!
	if _ := target.block_override(pos.x, pos.y, pos.z) {
		assert false
	}
	assert wait_for_sent_len(transport, 1, 5000)
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

struct ObstructionProbe {
	obstructed bool
	self_only  bool
}

fn probe_obstructed_by_entity(mut wr WorldRuntime, pos types.BlockPosition, acting_runtime_id u64) (bool, bool) {
	result := world_call[ObstructionProbe](mut wr, fn [pos, acting_runtime_id] (mut tx WorldTx) ObstructionProbe {
		obstructed, self_only := obstructed_by_entity(tx.wr, pos, acting_runtime_id)
		return ObstructionProbe{obstructed, self_only}
	}) or { panic('sync barrier rejected') }
	return result.obstructed, result.self_only
}

fn obstruction_test_session(mut hub Hub, mut wr WorldRuntime, name string, rid u64, pos types.Vector3) &NetworkSession {
	mut s := &NetworkSession{
		player:        &player.Player{
			identity: auth.Identity{
				display_name: name
			}
		}
		runtime_id:    rid
		hub:           hub
		world:         wr.world
		world_runtime: wr
	}
	s.player.reset_position(pos)
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn test_obstructed_by_entity_ignores_only_own_body() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}
	mut alex :=
		obstruction_test_session(mut hub, mut wr, 'Alex', 1, types.Vector3{0.5, player_eye_height, 0.5})

	// Alex's own body occupies (0,0,0), obstructed but self_only.
	obstructed, self_only := probe_obstructed_by_entity(mut wr, types.BlockPosition{0, 0, 0},
		alex.runtime_id)
	assert obstructed
	assert self_only

	// Nobody else occupies a faraway cell.
	clear_obstructed, clear_self_only := probe_obstructed_by_entity(mut wr, types.BlockPosition{50, 0, 50},
		alex.runtime_id)
	assert !clear_obstructed
	assert clear_self_only
}

fn test_obstructed_by_entity_blocks_other_player() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}
	mut alex :=
		obstruction_test_session(mut hub, mut wr, 'Alex', 1, types.Vector3{10.5, player_eye_height, 10.5})
	obstruction_test_session(mut hub, mut wr, 'Steve', 2, types.Vector3{0.5, player_eye_height, 0.5})

	obstructed, self_only := probe_obstructed_by_entity(mut wr, types.BlockPosition{0, 0, 0},
		alex.runtime_id)
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
		player:     make_test_player('Alex', protocol.game_type_survival)
		runtime_id: 1
		transport:  transport
		hub:        hub
		generator:  world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{0.5, f32(world.overworld.min_y + 1) + 0.5, 0.5})
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
	hub.set_current_tick(0)

	s.break_block(pos)!
	assert wait_for_sent_len(transport, 1, 5000)
	sent := transport.sent[0]
	if sent is protocol.UpdateBlockPacket {
		assert sent.block_runtime_id == dirt_id
	} else {
		assert false
	}
}

fn register_test_session(mut s NetworkSession) {
	mut wr := s.world_runtime
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
}

fn test_break_block_succeeds_after_ticks_elapsed() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := dirt_break_test_session(mut hub, mut transport)
	s.world = target
	s.world_runtime = hub.world_runtime('world') or { panic('expected world runtime') }
	register_test_session(mut s)

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := s.block_at(pos.x, pos.y, pos.z)
	s.breaking = BreakProgress{pos.x, pos.y, pos.z, dirt_id, 0}
	hub.set_current_tick(20)

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
	hub.set_current_tick(100)

	s.break_block(pos)!
	assert wait_for_sent_len(transport, 1, 5000)
	sent := transport.sent[0]
	if sent is protocol.UpdateBlockPacket {
		assert sent.block_runtime_id == dirt_id
	} else {
		assert false
	}
}

fn test_break_block_creative_bypasses_gating() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:        make_test_player('Alex', protocol.game_type_creative)
		runtime_id:    1
		transport:     transport
		hub:           hub
		world:         target
		world_runtime: hub.world_runtime('world') or { panic('expected world runtime') }
		generator:     world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{0.5, f32(world.overworld.min_y + 1) + 0.5, 0.5})
	hub.add(s)
	register_test_session(mut s)

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	hub.set_current_tick(0)

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
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	sign_id :=
		hub.blocks.get_by_name('minecraft:standing_sign') or { panic('missing sign') }.runtime_id()
	hub.items.register(item.BlockItem{
		id:            'minecraft:oak_sign'
		block_runtime: sign_id
	})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:        make_test_player('Alex', protocol.game_type_creative)
		runtime_id:    1
		transport:     transport
		hub:           hub
		world:         target
		world_runtime: hub.world_runtime('world') or { panic('expected world runtime') }
		generator:     world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{2.1901546, -58.37999, 10.302694})
	hub.add(s)
	register_test_session(mut s)

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

fn test_survival_place_ignores_client_claimed_held_item() {
	data := gamedata.GameData{
		item_id_by_name: {
			'minecraft:oak_sign': 390
		}
	}
	mut hub := new_hub(data)
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	sign_id :=
		hub.blocks.get_by_name('minecraft:standing_sign') or { panic('missing sign') }.runtime_id()
	hub.items.register(item.BlockItem{
		id:            'minecraft:oak_sign'
		block_runtime: sign_id
	})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:        make_test_player('Alex', protocol.game_type_survival)
		runtime_id:    1
		transport:     transport
		hub:           hub
		world:         target
		world_runtime: hub.world_runtime('world') or { panic('expected world runtime') }
		generator:     world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{2.1901546, -58.37999, 10.302694})
	hub.add(s)
	register_test_session(mut s)

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
					block_runtime_id: sign_id
				}
			}
			position:          types.Vector3{2.1901546, -58.37999, 10.302694}
			clicked_position:  types.Vector3{0.35214186, 1.0, 0.20941257}
			client_prediction: 1
		}
	}

	s.handle_inventory_transaction(place_packet)!

	assert s.block_at(2, -60, 12) == world.air.network_id
}

fn test_spectator_cannot_place_or_break_blocks() {
	mut hub := new_hub(gamedata.GameData{
		item_id_by_name: {
			'minecraft:test_block': 500
		}
	})
	hub.items.register(item.BlockItem{
		id:            'minecraft:test_block'
		block_runtime: world.bedrock.network_id
	})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	target.set_block(0, 0, 1, world.bedrock.network_id)
	target.set_block(0, world.overworld.min_y + 1, 0, world.dirt.network_id)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:        make_test_player('Alex', protocol.game_type_spectator)
		runtime_id:    1
		transport:     transport
		hub:           hub
		world:         target
		world_runtime: hub.world_runtime('world') or { panic('expected world runtime') }
		generator:     world.VoidGenerator{}
	}
	s.player.reset_position(types.Vector3{0.5, 1.62, 0.5})
	held_stack := types.ItemStack{
		id:               500
		count:            1
		block_runtime_id: world.bedrock.network_id
	}
	net_id := s.player.track_stack(held_stack)
	s.player.set_slot(s.player.held_slot(), net_id)
	hub.add(s)
	register_test_session(mut s)
	defer {
		hub.close_worlds()
	}

	place_packet := protocol.InventoryTransactionPacket{
		transaction_type: protocol.inventory_transaction_type_use_item
		use_item:         protocol.UseItemTransactionData{
			action_type:       protocol.item_use_action_click_block
			trigger_type:      1
			block_position:    types.BlockPosition{0, 0, 1}
			block_face:        1
			hotbar_slot:       0
			held_item:         types.ItemStackWrapper{
				item_stack: types.ItemStack{
					id:               500
					count:            64
					block_runtime_id: world.bedrock.network_id
				}
			}
			position:          types.Vector3{0.5, 1.62, 0.5}
			clicked_position:  types.Vector3{0.5, 1.0, 0.5}
			client_prediction: 1
		}
	}

	s.handle_inventory_transaction(place_packet)!
	assert target.block_override(0, 1, 1) == none

	mut break_transport := &FakeTransport{}
	mut breaker := dirt_break_test_session(mut hub, mut break_transport)
	breaker.player.set_game_mode(protocol.game_type_spectator)
	breaker.world = target
	breaker.world_runtime = hub.world_runtime('world') or { panic('expected world runtime') }
	breaker.generator = world.FlatGenerator{}
	register_test_session(mut breaker)
	break_pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := breaker.block_at(break_pos.x, break_pos.y, break_pos.z)
	breaker.breaking = BreakProgress{break_pos.x, break_pos.y, break_pos.z, dirt_id, 0}
	hub.set_current_tick(20)

	breaker.break_block(break_pos)!
	assert target.block_override(break_pos.x, break_pos.y, break_pos.z) or { -1 } == world.dirt.network_id
}

fn test_empty_hand_interact_places_nothing() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		player:        make_test_player('Alex', protocol.game_type_creative)
		runtime_id:    1
		transport:     transport
		hub:           hub
		world:         target
		world_runtime: hub.world_runtime('world') or { panic('expected world runtime') }
		generator:     world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{2.1901546, -58.37999, 10.302694})
	hub.add(s)
	register_test_session(mut s)

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
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 1
		hub:        hub
	}
	hub.add(s)
	stack := types.ItemStack{
		id:    300
		count: 1
	}
	net_id := s.player.track_stack(stack)
	s.player.set_slot(s.player.held_slot(), net_id)

	s.apply_consume_held_item()

	got, got_net := s.inventory_stack_at(s.player.held_slot())
	assert got_net == net_id
	assert got.count == 1
}

// pick_request_test_session builds a session bound to a real registered
// world with a known block id planted at the pick position via tx.set_block
// (rather than relying on a generator's own layer layout which is fragile
// to depend on for a specific numeric id).
fn pick_request_test_session(mut hub Hub, mode int, pos types.BlockPosition, block_id int) &NetworkSession {
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	world_call[bool](mut wr, fn [pos, block_id] (mut tx WorldTx) bool {
		tx.set_block(pos.x, pos.y, pos.z, block_id)
		return true
	}) or { panic('sync barrier rejected') }
	mut s := &NetworkSession{
		player:        make_test_player('Alex', mode)
		runtime_id:    1
		transport:     &FakeTransport{}
		hub:           hub
		world:         target
		world_runtime: wr
		generator:     world.FlatGenerator{}
	}
	hub.add(s)
	register_test_session(mut s)
	return s
}

fn test_block_pick_request_creative_adds_new_item_when_not_held() {
	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	mut hub := new_hub(gamedata.GameData{
		item_id_by_block: {
			42: 500
		}
	})
	mut s := pick_request_test_session(mut hub, protocol.game_type_creative, pos, 42)

	s.handle_block_pick_request(protocol.BlockPickRequestPacket{
		block_position: pos
	})!

	held, _ := s.inventory_stack_at(s.player.held_slot())
	assert held.id == 500
	assert held.block_runtime_id == 42
}

fn test_block_pick_request_survival_without_existing_item_is_noop() {
	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	mut hub := new_hub(gamedata.GameData{
		item_id_by_block: {
			42: 500
		}
	})
	mut s := pick_request_test_session(mut hub, protocol.game_type_survival, pos, 42)

	s.handle_block_pick_request(protocol.BlockPickRequestPacket{
		block_position: pos
	})!

	assert !s.player.has_slot(s.player.held_slot())
}

fn test_block_pick_request_selects_existing_item_into_hand() {
	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	mut hub := new_hub(gamedata.GameData{
		item_id_by_block: {
			42: 500
		}
	})
	mut s := pick_request_test_session(mut hub, protocol.game_type_survival, pos, 42)
	existing := types.ItemStack{
		id:               500
		count:            1
		block_runtime_id: 42
	}
	net_id := s.player.track_stack(existing)
	// A non-hotbar slot, so the pick takes the swap_slot_into_hand path
	// rather than the plain select_hotbar_slot one.
	s.player.set_slot(give_hotbar_size, net_id)

	s.handle_block_pick_request(protocol.BlockPickRequestPacket{
		block_position: pos
	})!

	held, held_net := s.inventory_stack_at(s.player.held_slot())
	assert held_net == net_id
	assert held.id == 500
}
