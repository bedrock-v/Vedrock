module session

import bedrock_v.protocol.types
import server.internal.gamedata
import server.player
import server.internal.auth
import server.world
import server.world.db

fn placed_break_session(mut hub Hub, mut transport FakeTransport, mut wr WorldRuntime) &NetworkSession {
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
		generator:     world.FlatGenerator{}
	}
	s.player.reset_position(types.Vector3{0.5, f32(world.overworld.min_y + 5) + 0.62, 2.5})
	hub.add(s)
	world_call[bool]('test', mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected') }
	return s
}

// complete_break fast forwards the tracked break progress, standing in for
// the world ticks a client would spend mining the block.
fn complete_break(mut s NetworkSession) {
	mut bp := s.breaking_snapshot() or { return }
	bp.progress = 1.0
	s.set_breaking(bp)
}

fn test_survival_placed_block_can_be_broken() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := placed_break_session(mut hub, mut transport, mut wr)
	defer {
		hub.close_worlds()
	}

	stack := types.ItemStack{
		id:               5
		count:            2
		block_runtime_id: world.cobblestone.network_id
	}
	net_id := s.player.track_stack(stack)
	s.player.set_slot(s.player.held_slot(), net_id)
	s.player.set_held(s.player.held_slot(), wrap_stack_id(stack, net_id))

	ground := types.BlockPosition{0, world.overworld.min_y + 3, 0}
	placed_pos := types.BlockPosition{0, world.overworld.min_y + 4, 0}
	assert s.block_at(ground.x, ground.y, ground.z) == world.grass_block.network_id
	assert s.block_at(placed_pos.x, placed_pos.y, placed_pos.z) == world.air.network_id

	s.handle_place_click(ground, 1, 0.5)

	assert target.block_override(placed_pos.x, placed_pos.y, placed_pos.z) or { -1 } == world.cobblestone.network_id

	s.handle_start_break(placed_pos, 1)
	complete_break(mut s)
	s.break_block(placed_pos)!

	assert target.block_override(placed_pos.x, placed_pos.y, placed_pos.z) or { -1 } == world.air.network_id
}

fn real_game_data() gamedata.GameData {
	return gamedata.load('../data') or {
		gamedata.load('data') or { panic('cannot find data dir: ${err}') }
	}
}

fn real_palette() &world.BlockPalette {
	return world.load_palette('../data/block_palette.nbt') or {
		world.load_palette('data/block_palette.nbt') or { panic('cannot load palette: ${err}') }
	}
}

fn test_survival_mined_drop_can_be_replaced_and_broken() {
	mut hub := new_hub(real_game_data())
	hub.palette = real_palette()
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := placed_break_session(mut hub, mut transport, mut wr)
	defer {
		hub.close_worlds()
	}

	ground := types.BlockPosition{0, world.overworld.min_y + 3, 0}
	placed_pos := types.BlockPosition{0, world.overworld.min_y + 4, 0}
	mined_id := s.block_at(0, world.overworld.min_y + 2, 0)
	assert mined_id == world.dirt.network_id

	drop_name, drop_count := block_drop_for(mut wr, mined_id)
	assert drop_name != ''
	assert drop_count > 0

	picked := types.ItemStack{
		id:    hub.data.item_id(drop_name)
		count: drop_count
	}
	assert picked.id != 0
	net_id := s.player.track_stack(picked)
	s.player.set_slot(s.player.held_slot(), net_id)
	s.player.set_held(s.player.held_slot(), wrap_stack_id(picked, net_id))

	assert s.placement_runtime_id() != 0

	s.handle_place_click(ground, 1, 0.5)

	placed_id := target.block_override(placed_pos.x, placed_pos.y, placed_pos.z) or { -1 }
	assert placed_id == world.dirt.network_id

	s.handle_start_break(placed_pos, 1)
	complete_break(mut s)
	s.break_block(placed_pos)!

	assert target.block_override(placed_pos.x, placed_pos.y, placed_pos.z) or { -1 } == world.air.network_id
}

fn test_survival_placed_block_can_be_broken_with_real_palette() {
	mut hub := new_hub(real_game_data())
	hub.palette = real_palette()
	target := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut transport := &FakeTransport{}
	mut s := placed_break_session(mut hub, mut transport, mut wr)
	defer {
		hub.close_worlds()
	}

	stack := types.ItemStack{
		id:               5
		count:            2
		block_runtime_id: world.cobblestone.network_id
	}
	net_id := s.player.track_stack(stack)
	s.player.set_slot(s.player.held_slot(), net_id)
	s.player.set_held(s.player.held_slot(), wrap_stack_id(stack, net_id))

	ground := types.BlockPosition{0, world.overworld.min_y + 3, 0}
	placed_pos := types.BlockPosition{0, world.overworld.min_y + 4, 0}

	s.handle_place_click(ground, 1, 0.5)

	placed_id := target.block_override(placed_pos.x, placed_pos.y, placed_pos.z) or { -1 }
	assert placed_id == world.cobblestone.network_id

	s.handle_start_break(placed_pos, 1)
	complete_break(mut s)
	s.break_block(placed_pos)!

	assert target.block_override(placed_pos.x, placed_pos.y, placed_pos.z) or { -1 } == world.air.network_id
}
