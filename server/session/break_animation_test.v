module session

import time
import bedrock_v.protocol.types
import server.internal.auth
import server.internal.gamedata
import server.player
import server.world
import server.world.db
import server.item
import server.block
import bedrock_v.protocol.current as proto

// A break that never starts shows the player no crack animation and no
// particles, which is the whole symptom of the server reading a different
// block than the client was sent.

fn animation_session(mut hub Hub, mut transport FakeTransport, mut wr WorldRuntime, generator world.Generator) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	pl.set_game_mode(.survival)
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		transport:     transport
		hub:           hub
		world_runtime: wr
		world:         wr.world
		generator:     generator
	}
	s.player.reset_position(types.Vector3{0.5, f32(world.overworld.min_y) + 1.62, 0.5})
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn sent_start_cracking(transport &FakeTransport, x int, y int, z int) bool {
	for p in transport.sent {
		if p is proto.LevelEventPacket {
			if p.event_id == proto.level_event_start_block_cracking && p.position[0] == f32(x)
				&& p.position[1] == f32(y) && p.position[2] == f32(z) {
				return true
			}
		}
	}
	return false
}

fn wait_for_start_cracking(transport &FakeTransport, x int, y int, z int, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for !sent_start_cracking(transport, x, y, z) {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return sent_start_cracking(transport, x, y, z)
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return sent_start_cracking(transport, x, y, z)
		}
	}
	return true
}

// populated_position finds a block only the full column build produces - a
// tree - which is what the generator's per block query answers air for.
fn populated_position(gen world.Generator, chunk world.Chunk) ?(int, int, int) {
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for y in 0 .. 120 {
				id := chunk.block_id(x, y, z)
				if id != world.air.network_id && chunk.block_id(x, y + 1, z) == world.air.network_id
					&& gen.block_at(x, y, z) == world.air.network_id {
					return x, y, z
				}
			}
		}
	}
	return none
}

fn test_mining_a_generated_tree_starts_the_crack_animation() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('trees', none, 'normal', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('trees') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	gen := world.new_generator('normal')
	mut s := animation_session(mut hub, mut transport, mut wr, gen)
	defer {
		hub.close_worlds()
	}

	chunk := s.generated_chunk(wr, 0, 0)
	x, y, z := populated_position(gen, chunk) or {
		assert false, 'no populated block in the first column'
		return
	}
	s.player.reset_position(types.Vector3{f32(x) + 0.5, f32(y) + 1.62, f32(z) + 0.5})

	s.handle_start_break(types.BlockPosition{x, y, z}, 1)

	assert wait_for_start_cracking(transport, x, y, z, 5000)
}

// Clicking a block the server reads as air is dropped as a placement, so the
// block never reaches the world and mining it later animates nothing either.
fn test_placing_against_generated_terrain_reaches_the_world() {
	mut hub := new_hub(gamedata.GameData{
		item_id_by_name: {
			'minecraft:test_block': 500
		}
	})
	item.register(block.BlockItem{
		id:            'minecraft:test_block'
		block_runtime: world.stone.network_id
	})
	target := db.new_world('trees', none, 'normal', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('trees') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	gen := world.new_generator('normal')
	mut s := animation_session(mut hub, mut transport, mut wr, gen)
	defer {
		hub.close_worlds()
	}

	chunk := s.generated_chunk(wr, 0, 0)
	x, y, z := populated_position(gen, chunk) or {
		assert false, 'no populated block in the first column'
		return
	}
	stack := types.ItemStack{
		id:    500
		count: 1
	}
	net_id := s.player.track_stack(stack)
	s.player.set_slot(s.player.held_slot(), net_id)
	s.player.set_held(s.player.held_slot(), wrap_stack_id(stack, net_id))
	s.player.reset_position(types.Vector3{f32(x) + 2.5, f32(y) + 2.0, f32(z) + 0.5})

	// Face 1 is the top, so the block lands on top of the one clicked.
	s.handle_place_click(types.BlockPosition{x, y, z}, 1, 1.0)

	assert target.block_override(x, y + 1, z) or { 0 } == world.stone.network_id
}

fn test_mining_a_placed_block_starts_the_crack_animation() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := animation_session(mut hub, mut transport, mut wr, world.VoidGenerator{})
	defer {
		hub.close_worlds()
	}

	y := world.overworld.min_y
	target.set_block(0, y, 1, world.stone.network_id)

	s.handle_start_break(types.BlockPosition{0, y, 1}, 1)

	assert wait_for_start_cracking(transport, 0, y, 1, 5000)
}
