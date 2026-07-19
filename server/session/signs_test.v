module session

import nbt
import protocol
import protocol.types
import server.internal.gamedata
import server.internal.auth
import server.world
import server.world.db

fn test_build_and_extract_sign_text_roundtrip() {
	root := build_sign_nbt(1, 2, 3, 'Hello world')
	compound := root.tag as nbt.Compound
	text := extract_sign_text(compound) or { panic('expected front text') }
	assert text == 'Hello world'

	x := compound.get('x') or { panic('missing x') }
	y := compound.get('y') or { panic('missing y') }
	z := compound.get('z') or { panic('missing z') }
	assert x as i32 == i32(1)
	assert y as i32 == i32(2)
	assert z as i32 == i32(3)
}

fn test_extract_sign_text_missing_front_text_is_none() {
	mut compound := nbt.new_compound()
	compound.set('id', nbt.Tag('Sign'))
	if _ := extract_sign_text(compound) {
		assert false
	}
}

fn test_extract_sign_text_wrong_shape_is_none() {
	mut compound := nbt.new_compound()
	compound.set('FrontText', nbt.Tag('not a compound'))
	if _ := extract_sign_text(compound) {
		assert false
	}
}

fn test_maybe_open_sign_editor_sends_for_sign_only() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut s := &NetworkSession{
		identity:   auth.Identity{
			display_name: 'Alex'
		}
		runtime_id: 1
		transport:  transport
		hub:        hub
	}
	hub.add(s)

	r := s.hub.blocks
	sign_id := r.get_by_name('minecraft:standing_sign') or { panic('missing sign') }.runtime_id()
	dirt_id := r.get_by_name('minecraft:dirt') or { panic('missing dirt') }.runtime_id()

	s.maybe_open_sign_editor(types.BlockPosition{0, 0, 0}, sign_id)
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.OpenSignPacket {
		assert sent.front
	} else {
		assert false
	}

	s.maybe_open_sign_editor(types.BlockPosition{1, 0, 0}, dirt_id)
	assert transport.sent.len == 1 // unchanged - dirt isn't a sign
}

fn test_handle_block_actor_data_persists_and_broadcasts_text() {
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
		position:   types.Vector3{0.5, player_eye_height, 0.5}
		generator:  world.VoidGenerator{}
	}
	hub.add(s)

	sign_id :=
		s.hub.blocks.get_by_name('minecraft:standing_sign') or { panic('missing sign') }.runtime_id()
	pos := types.BlockPosition{0, 0, 0}
	target.set_block(pos.x, pos.y, pos.z, sign_id)

	s.handle_block_actor_data(protocol.BlockActorDataPacket{
		block_position: pos
		nbt:            build_sign_nbt(pos.x, pos.y, pos.z, 'Welcome!')
	})!

	assert target.tile_text(pos.x, pos.y, pos.z) or { '' } == 'Welcome!'
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.BlockActorDataPacket {
		compound := sent.nbt.tag as nbt.Compound
		text := extract_sign_text(compound) or { panic('expected text') }
		assert text == 'Welcome!'
	} else {
		assert false
	}
}

fn test_handle_block_actor_data_ignores_non_sign_block() {
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
		position:   types.Vector3{0.5, player_eye_height, 0.5}
		generator:  world.VoidGenerator{}
	}
	hub.add(s)

	dirt_id := s.hub.blocks.get_by_name('minecraft:dirt') or { panic('missing dirt') }.runtime_id()
	pos := types.BlockPosition{0, 0, 0}
	target.set_block(pos.x, pos.y, pos.z, dirt_id)

	s.handle_block_actor_data(protocol.BlockActorDataPacket{
		block_position: pos
		nbt:            build_sign_nbt(pos.x, pos.y, pos.z, 'Should not be saved')
	})!

	if _ := target.tile_text(pos.x, pos.y, pos.z) {
		assert false
	}
	assert transport.sent.len == 0
}

fn test_create_sign_tile_initializes_empty_text_and_broadcasts() {
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
	}
	hub.add(s)

	sign_id :=
		s.hub.blocks.get_by_name('minecraft:standing_sign') or { panic('missing sign') }.runtime_id()
	pos := types.BlockPosition{5, 5, 5}

	s.create_sign_tile(pos, sign_id)

	assert target.tile_text(pos.x, pos.y, pos.z) or { 'missing' } == ''
	assert transport.sent.len == 1
	sent := transport.sent[0]
	if sent is protocol.BlockActorDataPacket {
		assert sent.block_position == pos
	} else {
		assert false
	}
}

fn test_create_sign_tile_ignores_non_sign_block() {
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
	}
	hub.add(s)

	dirt_id := s.hub.blocks.get_by_name('minecraft:dirt') or { panic('missing dirt') }.runtime_id()
	pos := types.BlockPosition{5, 5, 5}

	s.create_sign_tile(pos, dirt_id)

	if _ := target.tile_text(pos.x, pos.y, pos.z) {
		assert false
	}
	assert transport.sent.len == 0
}
