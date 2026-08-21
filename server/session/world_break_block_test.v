module session

import time

import protocol.types
import server.effect
import server.event
import server.internal.gamedata
import server.player
import server.internal.auth
import server.world
import server.world.db
import server.item
import protocol.current as proto

fn break_test_data() gamedata.GameData {
	return gamedata.GameData{
		item_id_by_name: {
			'minecraft:test_pick': 700
		}
	}
}

fn break_test_hub() &Hub {
	mut hub := new_hub(break_test_data())
	hub.items.register(item.ToolItem{
		id:             'minecraft:test_pick'
		tier:           .iron
		tool_type:      .pickaxe
		damage:         3.0
		max_durability: 100
		speed:          1.0
	})
	return hub
}

fn break_test_session(mut hub Hub, mut transport FakeTransport, mut wr WorldRuntime) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	pl.set_game_mode(proto.game_type_survival)
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		transport:     transport
		hub:           hub
		world_runtime: wr
		world:         wr.world
		generator:     world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{0.5, f32(world.overworld.min_y + 1) + 0.5, 0.5})
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn give_held_pick(mut s NetworkSession) {
	stack := types.ItemStack{
		id:    700
		count: 1
	}
	net_id := s.player.track_stack(stack)
	s.player.set_slot(s.player.held_slot(), net_id)
	s.player.set_held(s.player.held_slot(), wrap_stack_id(stack, net_id))
}

fn test_break_block_damages_held_item_exactly_once() {
	mut hub := break_test_hub()
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := break_test_session(mut hub, mut transport, mut wr)
	give_held_pick(mut s)
	defer {
		hub.close_worlds()
	}

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := s.block_at(pos.x, pos.y, pos.z)
	s.breaking = BreakProgress{
		x:            pos.x
		y:            pos.y
		z:            pos.z
		block_id:     dirt_id
		started_tick: 0
		progress:     1.0
	}
	hub.set_current_tick(20)

	s.break_block(pos)!

	assert target.block_override(pos.x, pos.y, pos.z) or { -1 } == world.air.network_id
	stack, _ := s.inventory_stack_at(s.player.held_slot())
	assert stack.meta == 1
}

struct BreakTestCancelHandler {
	event.NopHandler
}

fn (mut h BreakTestCancelHandler) on_block_break(mut ctx event.Context[event.BlockBreakData]) {
	ctx.cancel()
}

fn test_break_block_cancelled_leaves_block_and_item_unchanged() {
	mut hub := break_test_hub()
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	// block_break is dispatched on the owning world's own event bus, not
	// Hub's global one.
	wr.events.register(&BreakTestCancelHandler{}, .normal)
	mut transport := &FakeTransport{}
	mut s := break_test_session(mut hub, mut transport, mut wr)
	give_held_pick(mut s)
	defer {
		hub.close_worlds()
	}

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := s.block_at(pos.x, pos.y, pos.z)
	s.breaking = BreakProgress{
		x:            pos.x
		y:            pos.y
		z:            pos.z
		block_id:     dirt_id
		started_tick: 0
		progress:     1.0
	}
	hub.set_current_tick(20)

	s.break_block(pos)!

	assert target.block_override(pos.x, pos.y, pos.z) == none
	stack, _ := s.inventory_stack_at(s.player.held_slot())
	assert stack.meta == 0
}

fn test_break_observer_in_another_world_receives_no_packet() {
	mut hub := break_test_hub()
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	hub.set_default_world('world')
	other_world := db.new_world('other', none, 'flat', world.overworld)
	hub.add_world(other_world)
	mut other_wr := hub.world_runtime('other') or { panic('expected other world runtime') }
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut breaker_transport := &FakeTransport{}
	mut breaker := break_test_session(mut hub, mut breaker_transport, mut wr)
	give_held_pick(mut breaker)

	mut observer_transport := &FakeTransport{}
	mut observer := break_test_session(mut hub, mut observer_transport, mut other_wr)

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := breaker.block_at(pos.x, pos.y, pos.z)
	breaker.breaking = BreakProgress{
		x:            pos.x
		y:            pos.y
		z:            pos.z
		block_id:     dirt_id
		started_tick: 0
		progress:     1.0
	}
	hub.set_current_tick(20)

	breaker.break_block(pos)!

	assert target.block_override(pos.x, pos.y, pos.z) or { -1 } == world.air.network_id
	for p in observer_transport.sent {
		assert p !is proto.UpdateBlockPacket
	}
}

// CountingBreakHandler records block_break events to prove world scoped event
// isolation, not just packet isolation.
struct CountingBreakHandler {
	event.NopHandler
mut:
	hits int
}

fn (mut h CountingBreakHandler) on_block_break(mut ctx event.Context[event.BlockBreakData]) {
	h.hits++
}

// A handler registered on world B's event bus must never observe a block break
// that happened in world A, and vice versa.
fn test_break_block_event_isolated_to_owning_world() {
	mut hub := break_test_hub()
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	hub.set_default_world('world-a')
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut handler_a := &CountingBreakHandler{}
	mut handler_b := &CountingBreakHandler{}
	wr_a.events.register(handler_a, .normal)
	wr_b.events.register(handler_b, .normal)

	mut transport_a := &FakeTransport{}
	mut s_a := break_test_session(mut hub, mut transport_a, mut wr_a)
	give_held_pick(mut s_a)

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := s_a.block_at(pos.x, pos.y, pos.z)
	s_a.breaking = BreakProgress{
		x:            pos.x
		y:            pos.y
		z:            pos.z
		block_id:     dirt_id
		started_tick: 0
		progress:     1.0
	}
	hub.set_current_tick(20)

	s_a.break_block(pos)!

	assert handler_a.hits == 1
	assert handler_b.hits == 0
}

fn break_sent_level_event(transport &FakeTransport) bool {
	for p in transport.sent {
		if p is proto.LevelEventPacket {
			return true
		}
	}
	return false
}

// break_wait_for_level_event blocks on the session's outbound writer until it
// has actually sent a level event, since delivery is asynchronous.
fn break_wait_for_level_event(transport &FakeTransport, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for !break_sent_level_event(transport) {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return break_sent_level_event(transport)
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return break_sent_level_event(transport)
		}
	}
	return true
}

// Cracking animations are broadcast on the owning world's actor, so a player
// mining in world A must not animate blocks for a player in world B.
fn test_start_break_cracking_scoped_to_owning_world() {
	mut hub := break_test_hub()
	target := db.new_world('crack-a', none, 'flat', world.overworld)
	hub.add_world(target)
	hub.set_default_world('crack-a')
	other_world := db.new_world('crack-b', none, 'flat', world.overworld)
	hub.add_world(other_world)
	mut wr := hub.world_runtime('crack-a') or { panic('expected crack-a runtime') }
	mut other_wr := hub.world_runtime('crack-b') or { panic('expected crack-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut breaker_transport := &FakeTransport{}
	mut breaker := break_test_session(mut hub, mut breaker_transport, mut wr)
	give_held_pick(mut breaker)

	mut observer_transport := &FakeTransport{}
	break_test_session(mut hub, mut observer_transport, mut other_wr)

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	breaker.handle_start_break(pos, 1)

	assert break_wait_for_level_event(breaker_transport, 5000)
	assert !break_wait_for_level_event(observer_transport, 500)
}

// Haste adds a flat 20% mining speed per level and mining fatigue drops the
// speed to a fixed fraction per level. Both used to be modelled as compounding
// curves, which made a hasted player mine far faster than vanilla.
fn test_effects_scale_break_progress_like_vanilla() {
	mut hub := break_test_hub()
	target := db.new_world('effects', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('effects') or { panic('expected effects runtime') }
	mut transport := &FakeTransport{}
	mut s := break_test_session(mut hub, mut transport, mut wr)
	give_held_pick(mut s)
	defer {
		hub.close_worlds()
	}

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := s.block_at(pos.x, pos.y, pos.z)
	base := s.break_progress_per_tick(dirt_id)

	s.player.add_effect_result(effect.new(effect.haste, 2, 30 * time.second))
	hasted := s.break_progress_per_tick(dirt_id)
	assert_break_close(hasted / base, 1.4)

	s.player.remove_effect(effect.haste)
	s.player.add_effect_result(effect.new(effect.mining_fatigue, 1, 30 * time.second))
	fatigued := s.break_progress_per_tick(dirt_id)
	assert_break_close(fatigued / base, 0.3)
}

fn assert_break_close(got f32, want f32) {
	assert got > want - 0.001 && got < want + 0.001
}

// break_seconds_for converts the tracked per tick progress back into the time
// the block takes, which is the number the vanilla tables are written in.
fn break_seconds_for(s &NetworkSession, runtime_id int) f32 {
	return 1.0 / (20.0 * s.break_progress_per_tick(runtime_id))
}

// A player standing on a block must mine at full speed. The in air penalty is
// a factor of five, so taking it from the client's ground flag made every
// block take five times its vanilla time whenever that flag was not set.
fn test_standing_player_mines_at_vanilla_speed() {
	mut hub := break_test_hub()
	target := db.new_world('ground', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('ground') or { panic('expected ground runtime') }
	mut transport := &FakeTransport{}
	mut s := break_test_session(mut hub, mut transport, mut wr)
	defer {
		hub.close_worlds()
	}

	feet_y := world.overworld.min_y + 4
	s.player.reset_position(types.Vector3{0.5, f32(feet_y), 0.5})
	target.set_block(0, feet_y - 1, 0, world.cobblestone.network_id)
	assert s.supported_by_ground()

	// Cobblestone by hand is 10 seconds in vanilla: hardness 2.0, no pickaxe.
	assert_break_close(break_seconds_for(s, world.cobblestone.network_id), 10.0)

	// Stepping off that block restores the in air penalty.
	target.set_block(0, feet_y - 1, 0, world.air.network_id)
	assert !s.supported_by_ground()
	assert_break_close(break_seconds_for(s, world.cobblestone.network_id), 50.0)
}

// tick_world_once runs one simulation step on the owning world actor, the same
// entry point the tick loop uses.
fn tick_world_once(mut wr WorldRuntime) {
	world_call[bool](mut wr, fn (mut tx WorldTx) bool {
		tx.tick_effects()
		return true
	}) or { panic('tick rejected - world unexpectedly stopped') }
}

// The client leaves block breaking to the server, so a block has to be
// destroyed by the server's own tracked progress reaching one. Nothing else
// removes it: no destroy packet is sent here on purpose.
fn test_server_finishes_the_break_without_a_client_destroy() {
	mut hub := break_test_hub()
	target := db.new_world('server-break', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('server-break') or { panic('expected runtime') }
	mut transport := &FakeTransport{}
	mut s := break_test_session(mut hub, mut transport, mut wr)
	give_held_pick(mut s)
	defer {
		hub.close_worlds()
	}

	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	assert old_id != world.air.network_id

	s.handle_start_break(pos, 1)
	speed := s.break_progress_per_tick(old_id)
	assert speed > 0
	needed := int(1.0 / speed) + 2

	for _ in 0 .. needed {
		tick_world_once(mut wr)
		if s.breaking_snapshot() == none {
			break
		}
	}

	assert target.block_override(pos.x, pos.y, pos.z) or { -1 } == world.air.network_id
	assert s.breaking_snapshot() == none
}

struct BreakBarrierTask {
	started chan bool
	release chan bool
}

fn (t BreakBarrierTask) name() string {
	return 'BreakBarrierTask'
}

fn (t BreakBarrierTask) run(mut tx WorldTx) {
	t.started <- true
	_ := <-t.release
}

fn test_break_in_one_world_does_not_stall_break_in_another() {
	mut hub := break_test_hub()
	world_a := db.new_world('stall-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	hub.set_default_world('stall-a')
	world_b := db.new_world('progress-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('stall-a') or { panic('expected stall-a runtime') }
	mut wr_b := hub.world_runtime('progress-b') or { panic('expected progress-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut transport_b := &FakeTransport{}
	mut s_b := break_test_session(mut hub, mut transport_b, mut wr_b)
	give_held_pick(mut s_b)

	// Stall world A's actor with a task barrier.
	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	a_ok := wr_a.submit(BreakBarrierTask{
		started: started
		release: release
	})
	assert a_ok
	_ := <-started

	// Breaking in world B must complete promptly even while A is stalled.
	pos := types.BlockPosition{0, world.overworld.min_y + 1, 0}
	dirt_id := s_b.block_at(pos.x, pos.y, pos.z)
	s_b.breaking = BreakProgress{
		x:            pos.x
		y:            pos.y
		z:            pos.z
		block_id:     dirt_id
		started_tick: 0
		progress:     1.0
	}
	hub.set_current_tick(20)
	s_b.break_block(pos)!

	assert world_b.block_override(pos.x, pos.y, pos.z) or { -1 } == world.air.network_id

	release <- true
}
