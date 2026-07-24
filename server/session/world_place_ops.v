module session

import protocol
import protocol.types
import server.event
import server.world
import server.block

// obstructed_by_entity reports whether pos overlaps a player registered in
// wr, including the acting player's own current or pending body position.
// Actor only: reads wr.players directly, so must only be called from
// within a WorldTx operation.
fn obstructed_by_entity(wr &WorldRuntime, pos types.BlockPosition, acting_runtime_id u64) (bool, bool) {
	block_min_x := f32(pos.x)
	block_max_x := f32(pos.x) + 1
	block_min_y := f32(pos.y)
	block_max_y := f32(pos.y) + 1
	block_min_z := f32(pos.z)
	block_max_z := f32(pos.z) + 1
	mut obstructed := false
	for mut entry in wr.players.values() {
		tp := if entry.session.runtime_id == acting_runtime_id {
			entry.session.effective_position()
		} else {
			entry.session.current_position()
		}
		feet_y := tp.y - player_eye_height
		min_x := tp.x - player_half_width
		max_x := tp.x + player_half_width
		min_y := feet_y
		max_y := feet_y + player_height
		min_z := tp.z - player_half_width
		max_z := tp.z + player_half_width
		overlaps := min_x < block_max_x && max_x > block_min_x && min_y < block_max_y
			&& max_y > block_min_y && min_z < block_max_z && max_z > block_min_z
		if !overlaps {
			continue
		}
		obstructed = true
		if entry.session.runtime_id == acting_runtime_id {
			continue
		}
		return true, false
	}
	return obstructed, true
}

// is_replaceable reports whether block_id is silently overwritten by a
// placement rather than blocking it (short grass, ferns, etc.).
fn (tx &WorldTx) is_replaceable(block_id int) bool {
	b := tx.wr.hub.blocks.get(block_id) or { return false }
	if b is block.Replaceable {
		return b.replaceable()
	}
	return false
}

fn (tx &WorldTx) can_place_block_on_face(runtime_id int, click_face int, support_id int) bool {
	if isnil(tx.wr.hub.palette) {
		return true
	}
	return tx.wr.hub.palette.can_place_on_support(runtime_id, click_face, support_id)
}

// oriented_block resolves a directional block's runtime id from the acting
// player's yaw and the clicked face. Falls back to the raw id when no
// palette is loaded.
fn (tx &WorldTx) oriented_block(runtime_id int, click_face int, click_y f32, yaw f32) int {
	if isnil(tx.wr.hub.palette) {
		return runtime_id
	}
	return tx.wr.hub.palette.oriented(runtime_id, yaw, click_face, click_y)
}

fn (tx &WorldTx) merged_slab(existing_id int, placing_id int, click_face int, click_y f32, clicked bool) ?int {
	if existing_id == world.air.network_id || isnil(tx.wr.hub.palette) {
		return none
	}
	return tx.wr.hub.palette.merged_slab(existing_id, placing_id, click_face, click_y, clicked)
}

fn (mut tx WorldTx) door_placement(runtime_id int, pos types.BlockPosition, click_face int, yaw f32) ?world.DoorPlacement {
	if click_face != 1 || isnil(tx.wr.hub.palette) {
		return none
	}
	above := face_offset(pos, 1)
	below := face_offset(pos, 0)
	dim := tx.wr.world.dimension
	if pos.y < dim.min_y || above.y > dim.max_y() {
		return none
	}
	if tx.block_at(pos.x, pos.y, pos.z) != world.air.network_id
		|| tx.block_at(above.x, above.y, above.z) != world.air.network_id {
		return none
	}
	below_id := tx.block_at(below.x, below.y, below.z)
	if !tx.wr.hub.palette.model(below_id).face_solid(1) {
		return none
	}
	return tx.wr.hub.palette.door_placement(runtime_id, yaw, tx.neighbor_ids(pos))
}

fn (tx &WorldTx) door_pair_pos(pos types.BlockPosition, id int) ?types.BlockPosition {
	if isnil(tx.wr.hub.palette) {
		return none
	}
	_ := tx.wr.hub.palette.door_pair_id(id) or { return none }
	if tx.wr.hub.palette.is_door_top(id) {
		return face_offset(pos, 0)
	}
	return face_offset(pos, 1)
}

fn (tx &WorldTx) door_pair_matches(id int, pair_id int) bool {
	if isnil(tx.wr.hub.palette) {
		return false
	}
	expected := tx.wr.hub.palette.door_pair_id(id) or { return false }
	return expected == pair_id
}

fn (tx &WorldTx) carve_pumpkin(mut s NetworkSession, old_id int, click_face int) ?int {
	_, name := s.held_stack_and_name()
	if name != 'minecraft:shears' {
		return none
	}
	return tx.wr.hub.palette.carved_pumpkin_id(old_id, click_face)
}

// create_sign_tile initializes a newly placed sign's block entity text and
// tells observers about it. Called before the block mutation itself
// broadcasts, so an observer never sees the block exist without its tile.
fn (mut tx WorldTx) create_sign_tile(pos types.BlockPosition, runtime_id int) {
	b := tx.wr.hub.blocks.get(runtime_id) or { return }
	if b !is block.SignBlock {
		return
	}
	tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, '')
	tx.wr.broadcast_world(&protocol.BlockActorDataPacket{
		block_position: pos
		nbt:            build_sign_nbt(pos.x, pos.y, pos.z, '')
	})
}

fn (mut tx WorldTx) maybe_open_sign_editor(mut s NetworkSession, pos types.BlockPosition, runtime_id int) {
	b := tx.wr.hub.blocks.get(runtime_id) or { return }
	if b !is block.SignBlock {
		return
	}
	s.deliver(&protocol.OpenSignPacket{
		block_position: pos
		front:          true
	})
}

// interact_block runs old_id's right click behaviour, if any, at pos. false
// means the caller should fall through to placement handling.
fn (mut tx WorldTx) interact_block(mut s NetworkSession, pos types.BlockPosition, old_id int, click_face int) bool {
	if b := tx.wr.hub.blocks.get(old_id) {
		if b is block.SignBlock {
			tx.maybe_open_sign_editor(mut s, pos, old_id)
			return true
		}
	}
	if isnil(tx.wr.hub.palette) {
		return false
	}
	if new_id := tx.carve_pumpkin(mut s, old_id, click_face) {
		tx.set_block(pos.x, pos.y, pos.z, new_id)
		tx.broadcast_swing(s)
		tx.notify_block_changed(pos)
		return true
	}
	if pair := tx.door_pair_pos(pos, old_id) {
		pair_id := tx.block_at(pair.x, pair.y, pair.z)
		if toggled := tx.wr.hub.palette.door_toggled_pair(old_id, pair_id) {
			tx.set_block(pos.x, pos.y, pos.z, toggled.clicked)
			tx.set_block(pair.x, pair.y, pair.z, toggled.pair)
			tx.broadcast_swing(s)
			tx.notify_block_changed(pair)
			tx.notify_block_changed(pos)
			return true
		}
		return false
	}
	if new_id := tx.wr.hub.palette.toggled_open(old_id) {
		tx.set_block(pos.x, pos.y, pos.z, new_id)
		tx.broadcast_swing(s)
		tx.notify_block_changed(pos)
		return true
	}
	interactable := tx.wr.hub.blocks.get(old_id) or { return false }
	if interactable is block.Interactable {
		if !interactable.interact(pos.x, pos.y, pos.z, click_face, mut tx.wr.world) {
			return false
		}
		new_id := tx.block_at(pos.x, pos.y, pos.z)
		tx.broadcast_block(pos.x, pos.y, pos.z, new_id)
		tx.broadcast_swing(s)
		tx.notify_block_changed(pos)
		return true
	}
	return false
}

// use_item_on_block applies the held item's UsableOnBlockItem effect (e.g.
// bone meal advancing a crop's growth stage) if clicked_id qualifies.
// Returns false for every item/block combination that doesn't.
fn (mut tx WorldTx) use_item_on_block(mut s NetworkSession, pos types.BlockPosition, clicked_id int) bool {
	if isnil(tx.wr.hub.palette) {
		return false
	}
	v := tx.wr.hub.palette.variant(clicked_id) or { return false }
	stack, name := s.held_stack_and_name()
	result := tx.wr.hub.items.use_on_block_result(name, v.name, stack.meta) or { return false }
	current := v.states[result.state_key] or { return false }.int()
	new_id := tx.wr.hub.palette.with_state(clicked_id, result.state_key, (current +
		result.state_delta).str()) or { return false }
	if new_id == clicked_id {
		return false
	}
	mut use_ctx := event.new_context(event.ItemUseData{
		player:    s
		item_name: name
		meta:      stack.meta
		on_block:  true
		x:         pos.x
		y:         pos.y
		z:         pos.z
	})
	s.hub.events.item_use(mut use_ctx)
	if use_ctx.is_cancelled() {
		s.resend_block(pos)
		return true
	}
	tx.set_block(pos.x, pos.y, pos.z, new_id)
	if result.sound != '' {
		tx.wr.broadcast_world(&protocol.LevelSoundEventPacket{
			sound:           result.sound
			position:        s.current_position()
			extra_data:      -1
			entity_type:     'minecraft:player'
			actor_unique_id: i64(s.runtime_id)
		})
	}
	tx.broadcast_swing(s)
	if s.player.game_mode() != protocol.game_type_creative {
		tx.consume_held_item(mut s)
	}
	tx.notify_block_changed(pos)
	return true
}

// place_block_form places runtime_id at pos as an ordinary (non replacing)
// placement: rejects on occupancy/entity obstruction, dispatches the
// cancellable block_place event, then commits.
fn (mut tx WorldTx) place_block_form(mut s NetworkSession, pos types.BlockPosition, runtime_id int) bool {
	occupied := tx.block_at(pos.x, pos.y, pos.z) != world.air.network_id
	obstructed, self_only := obstructed_by_entity(tx.wr, pos, s.runtime_id)
	if occupied || obstructed {
		if occupied || !self_only {
			s.resend_block(pos)
		}
		return false
	}
	mut ctx := event.new_context(event.BlockPlaceData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: runtime_id
	})
	tx.wr.events.block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return false
	}
	// Tile initialized before the block mutation broadcasts, so an observer
	// can never see the block exist without its tile.
	tx.create_sign_tile(pos, runtime_id)
	tx.set_block(pos.x, pos.y, pos.z, runtime_id)
	tx.broadcast_swing(s)
	tx.notify_block_changed(pos)
	tx.maybe_open_sign_editor(mut s, pos, runtime_id)
	return true
}

// replace_block_form overwrites an existing replaceable block (e.g. merging
// into a double slab).
fn (mut tx WorldTx) replace_block_form(mut s NetworkSession, pos types.BlockPosition, runtime_id int) bool {
	mut ctx := event.new_context(event.BlockPlaceData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: runtime_id
	})
	tx.wr.events.block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return false
	}
	tx.create_sign_tile(pos, runtime_id)
	tx.set_block(pos.x, pos.y, pos.z, runtime_id)
	tx.broadcast_swing(s)
	tx.notify_block_changed(pos)
	tx.maybe_open_sign_editor(mut s, pos, runtime_id)
	return true
}

// place_door_pair places both halves of a door as a single transaction.
// Both positions are validated and one block_place event is dispatched
// before either half is written.
fn (mut tx WorldTx) place_door_pair(mut s NetworkSession, pos types.BlockPosition, parts world.DoorPlacement) bool {
	above := face_offset(pos, 1)
	obstructed_lower, lower_self := obstructed_by_entity(tx.wr, pos, s.runtime_id)
	obstructed_upper, upper_self := obstructed_by_entity(tx.wr, above, s.runtime_id)
	if obstructed_lower || obstructed_upper {
		if !lower_self {
			s.resend_block(pos)
		}
		if !upper_self {
			s.resend_block(above)
		}
		return false
	}
	mut ctx := event.new_context(event.BlockPlaceData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: parts.lower
	})
	tx.wr.events.block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		s.resend_block(above)
		return false
	}
	tx.set_block(pos.x, pos.y, pos.z, parts.lower)
	tx.set_block(above.x, above.y, above.z, parts.upper)
	tx.broadcast_swing(s)
	tx.notify_block_changed(pos)
	tx.notify_block_changed(above)
	return true
}
