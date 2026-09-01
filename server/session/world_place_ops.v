module session

import bedrock_v.protocol.types
import server.event
import server.world
import server.block
import server.item
import bedrock_v.protocol.current as proto
import server.player
import server.worldrt

// ObstructionResult is obstructed_by_entity's answer: whether pos is
// obstructed at all and whether the only body overlapping it is the acting
// player's own (which placement/break logic treats differently than a
// stranger's).
struct ObstructionResult {
	obstructed bool
	self_only  bool
}

// obstructed_by_entity reports whether pos overlaps a player registered in
// wr, including the acting player's own current or pending body position.
// Actor only: reads the world's actor registry directly, so must only be
// called from within a worldrt.WorldTx operation.
fn obstructed_by_entity(mut wr worldrt.WorldRuntime, pos types.BlockPosition, acting_runtime_id u64) ObstructionResult {
	block_min_x := f32(pos.x)
	block_max_x := f32(pos.x) + 1
	block_min_y := f32(pos.y)
	block_max_y := f32(pos.y) + 1
	block_min_z := f32(pos.z)
	block_max_z := f32(pos.z) + 1
	mut obstructed := false
	for mut a in wr.entities.player_actors() {
		if mut a is NetworkSession {
			tp := if a.runtime_id == acting_runtime_id {
				a.effective_position()
			} else {
				a.current_position()
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
			if overlaps {
				obstructed = true
				if a.runtime_id != acting_runtime_id {
					return ObstructionResult{true, false}
				}
			}
		}
	}
	return ObstructionResult{obstructed, true}
}

// is_replaceable reports whether block_id is silently overwritten by a
// placement rather than blocking it (short grass, ferns, etc.).
fn is_replaceable(block_id int) bool {
	b := block.get(block_id) or { return false }
	if b is block.Replaceable {
		return b.replaceable()
	}
	return false
}

fn can_place_block_on_face(tx &worldrt.WorldTx, runtime_id int, click_face int, support_id int) bool {
	if isnil(tx.wr.services.block_palette()) {
		return true
	}
	return tx.wr.services.block_palette().can_place_on_support(runtime_id, click_face, support_id)
}

// oriented_block resolves a directional block's runtime id from the acting
// player's yaw and the clicked face. Falls back to the raw id when no
// palette is loaded.
fn oriented_block(tx &worldrt.WorldTx, runtime_id int, click_face int, click_y f32, yaw f32) int {
	if isnil(tx.wr.services.block_palette()) {
		return runtime_id
	}
	return tx.wr.services.block_palette().oriented(runtime_id, yaw, click_face, click_y)
}

fn merged_slab(tx &worldrt.WorldTx, existing_id int, placing_id int, click_face int, click_y f32, clicked bool) ?int {
	if existing_id == world.air.network_id || isnil(tx.wr.services.block_palette()) {
		return none
	}
	return tx.wr.services.block_palette().merged_slab(existing_id, placing_id, click_face, click_y, clicked)
}

fn door_placement(mut tx worldrt.WorldTx, runtime_id int, pos types.BlockPosition, click_face int, yaw f32) ?world.DoorPlacement {
	if click_face != 1 || isnil(tx.wr.services.block_palette()) {
		return none
	}
	above := face_offset(pos, 1)
	below := face_offset(pos, 0)
	dim := tx.wr.world.dimension
	if pos.y < dim.min_y || above.y > dim.max_y() {
		return none
	}
	if block_at(tx, pos.x, pos.y, pos.z) != world.air.network_id
		|| block_at(tx, above.x, above.y, above.z) != world.air.network_id {
		return none
	}
	below_id := block_at(tx, below.x, below.y, below.z)
	if !tx.wr.services.block_palette().model(below_id).face_solid(1) {
		return none
	}
	return tx.wr.services.block_palette().door_placement(runtime_id, yaw, neighbor_ids(tx, pos))
}

fn door_pair_pos(tx &worldrt.WorldTx, pos types.BlockPosition, id int) ?types.BlockPosition {
	if isnil(tx.wr.services.block_palette()) {
		return none
	}
	_ := tx.wr.services.block_palette().door_pair_id(id) or { return none }
	if tx.wr.services.block_palette().is_door_top(id) {
		return face_offset(pos, 0)
	}
	return face_offset(pos, 1)
}

fn door_pair_matches(tx &worldrt.WorldTx, id int, pair_id int) bool {
	if isnil(tx.wr.services.block_palette()) {
		return false
	}
	expected := tx.wr.services.block_palette().door_pair_id(id) or { return false }
	return expected == pair_id
}

fn carve_pumpkin(tx &worldrt.WorldTx, mut s NetworkSession, old_id int, click_face int) ?int {
	_, name := s.held_stack_and_name()
	if name != 'minecraft:shears' {
		return none
	}
	return tx.wr.services.block_palette().carved_pumpkin_id(old_id, click_face)
}

// create_sign_tile initializes a newly placed sign's block entity text and
// tells observers about it. Called before the block mutation itself
// broadcasts, so an observer never sees the block exist without its tile.
fn create_sign_tile(mut tx worldrt.WorldTx, pos types.BlockPosition, runtime_id int) {
	b := block.get(runtime_id) or { return }
	if b !is block.SignBlock {
		return
	}
	tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, '')
	tx.wr.broadcast_world(&proto.BlockActorDataPacket{
		block_position:  proto.block_pos(pos)
		actor_data_tags: build_sign_nbt(pos.x, pos.y, pos.z, '')
	})
}

// create_note_tile initializes a newly placed note block's block entity
// text to pitch 0, matching create_sign_tile's pattern.
fn create_note_tile(mut tx worldrt.WorldTx, pos types.BlockPosition, runtime_id int) {
	b := block.get(runtime_id) or { return }
	if b !is block.NoteBlock {
		return
	}
	tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, '0')
	tx.wr.broadcast_world(&proto.BlockActorDataPacket{
		block_position:  proto.block_pos(pos)
		actor_data_tags: build_note_block_nbt(pos.x, pos.y, pos.z, 0)
	})
}

// create_jukebox_tile initializes a newly placed jukebox's block entity
// text to "no record", matching create_sign_tile's pattern.
fn create_jukebox_tile(mut tx worldrt.WorldTx, pos types.BlockPosition, runtime_id int) {
	b := block.get(runtime_id) or { return }
	if b !is block.JukeboxBlock {
		return
	}
	tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, '')
	tx.wr.broadcast_world(&proto.BlockActorDataPacket{
		block_position:  proto.block_pos(pos)
		actor_data_tags: build_jukebox_nbt(pos.x, pos.y, pos.z, '')
	})
}

fn maybe_open_sign_editor(mut s NetworkSession, pos types.BlockPosition, runtime_id int) {
	b := block.get(runtime_id) or { return }
	if b !is block.SignBlock {
		return
	}
	s.deliver(&proto.OpenSignPacket{
		pos:      proto.block_pos(pos)
		is_front: true
	})
}

// interact_block runs old_id's right click behaviour, if any, at pos. false
// means the caller should fall through to placement handling.
fn interact_block(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition, old_id int, click_face int) bool {
	if b := block.get(old_id) {
		if b is block.SignBlock {
			maybe_open_sign_editor(mut s, pos, old_id)
			return true
		}
		if b is block.ChestBlock {
			open_chest_container(mut tx, mut s, pos)
			return true
		}
		if b is block.CraftingTableBlock {
			open_workbench(mut tx, mut s, pos)
			return true
		}
		if b is block.NoteBlock {
			play_note(mut tx, mut s, pos)
			return true
		}
		if b is block.JukeboxBlock {
			interact_jukebox(mut tx, mut s, pos)
			return true
		}
	}
	if isnil(tx.wr.services.block_palette()) {
		return false
	}
	if new_id := carve_pumpkin(tx, mut s, old_id, click_face) {
		tx.set_block(pos.x, pos.y, pos.z, new_id)
		broadcast_swing(mut tx, s)
		notify_block_changed(mut tx, pos)
		return true
	}
	if pair := door_pair_pos(tx, pos, old_id) {
		pair_id := block_at(tx, pair.x, pair.y, pair.z)
		if toggled := tx.wr.services.block_palette().door_toggled_pair(old_id, pair_id) {
			tx.set_block(pos.x, pos.y, pos.z, toggled.clicked)
			tx.set_block(pair.x, pair.y, pair.z, toggled.pair)
			broadcast_swing(mut tx, s)
			notify_block_changed(mut tx, pair)
			notify_block_changed(mut tx, pos)
			return true
		}
		return false
	}
	if new_id := tx.wr.services.block_palette().toggled_open(old_id) {
		tx.set_block(pos.x, pos.y, pos.z, new_id)
		broadcast_swing(mut tx, s)
		notify_block_changed(mut tx, pos)
		return true
	}
	interactable := block.get(old_id) or { return false }
	if interactable is block.Interactable {
		if !interactable.interact(pos.x, pos.y, pos.z, click_face, mut tx.wr.world) {
			return false
		}
		new_id := block_at(tx, pos.x, pos.y, pos.z)
		tx.broadcast_block(pos.x, pos.y, pos.z, new_id)
		broadcast_swing(mut tx, s)
		notify_block_changed(mut tx, pos)
		return true
	}
	return false
}

// use_item_on_block applies the held item's UsableOnBlockItem effect (e.g.
// bone meal advancing a crop's growth stage) if clicked_id qualifies.
// Returns false for every item/block combination that doesn't.
fn use_item_on_block(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition, clicked_id int) bool {
	if isnil(tx.wr.services.block_palette()) {
		return false
	}
	v := tx.wr.services.block_palette().variant(clicked_id) or { return false }
	stack, name := s.held_stack_and_name()
	result := item.use_on_block_result(name, v.name, stack.meta) or { return false }
	current := v.states.get(result.state_key) or { return false }.int()
	new_id := tx.wr.services.block_palette().with_state(clicked_id, result.state_key, (current +
		result.state_delta).str()) or { return false }
	if new_id == clicked_id {
		return false
	}
	mut use_ctx := event.new_context(player.ItemUseData{
		player:    s
		item_name: name
		meta:      stack.meta
		on_block:  true
		x:         pos.x
		y:         pos.y
		z:         pos.z
	})
	s.handler.on_item_use(mut use_ctx)
	if use_ctx.is_cancelled() {
		s.resend_block(pos)
		return true
	}
	tx.set_block(pos.x, pos.y, pos.z, new_id)
	if result.sound != '' {
		tx.wr.broadcast_world(proto.level_sound_event(result.sound, s.current_position(), -1,
			'minecraft:player', s.runtime_id))
	}
	broadcast_swing(mut tx, s)
	if s.player.game_mode() != .creative {
		consume_held_item(mut s)
	}
	notify_block_changed(mut tx, pos)
	return true
}

// place_block_form places runtime_id at pos as an ordinary (non replacing)
// placement: rejects on occupancy/entity obstruction, dispatches the
// cancellable block_place event, then commits.
fn place_block_form(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition, runtime_id int) bool {
	occupied := block_at(tx, pos.x, pos.y, pos.z) != world.air.network_id
	obstruction := obstructed_by_entity(mut tx.wr, pos, s.runtime_id)
	if occupied || obstruction.obstructed {
		if occupied || !obstruction.self_only {
			s.resend_block(pos)
		}
		return false
	}
	mut ctx := event.new_context(player.BlockPlaceData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: runtime_id
	})
	s.handler.on_block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return false
	}
	// Tile initialized before the block mutation broadcasts, so an observer
	// can never see the block exist without its tile.
	create_sign_tile(mut tx, pos, runtime_id)
	create_note_tile(mut tx, pos, runtime_id)
	create_jukebox_tile(mut tx, pos, runtime_id)
	tx.set_block(pos.x, pos.y, pos.z, runtime_id)
	broadcast_place_sound(mut tx, s, pos.x, pos.y, pos.z, runtime_id)
	broadcast_swing(mut tx, s)
	notify_block_changed(mut tx, pos)
	maybe_open_sign_editor(mut s, pos, runtime_id)
	return true
}

// replace_block_form overwrites an existing replaceable block (e.g. merging
// into a double slab).
fn replace_block_form(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition, runtime_id int) bool {
	mut ctx := event.new_context(player.BlockPlaceData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: runtime_id
	})
	s.handler.on_block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return false
	}
	create_sign_tile(mut tx, pos, runtime_id)
	create_note_tile(mut tx, pos, runtime_id)
	create_jukebox_tile(mut tx, pos, runtime_id)
	tx.set_block(pos.x, pos.y, pos.z, runtime_id)
	broadcast_place_sound(mut tx, s, pos.x, pos.y, pos.z, runtime_id)
	broadcast_swing(mut tx, s)
	notify_block_changed(mut tx, pos)
	maybe_open_sign_editor(mut s, pos, runtime_id)
	return true
}

// place_door_pair places both halves of a door as a single transaction.
// Both positions are validated and one block_place event is dispatched
// before either half is written.
fn place_door_pair(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition, parts world.DoorPlacement) bool {
	above := face_offset(pos, 1)
	lower := obstructed_by_entity(mut tx.wr, pos, s.runtime_id)
	upper := obstructed_by_entity(mut tx.wr, above, s.runtime_id)
	if lower.obstructed || upper.obstructed {
		if !lower.self_only {
			s.resend_block(pos)
		}
		if !upper.self_only {
			s.resend_block(above)
		}
		return false
	}
	mut ctx := event.new_context(player.BlockPlaceData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: parts.lower
	})
	s.handler.on_block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		s.resend_block(above)
		return false
	}
	tx.set_block(pos.x, pos.y, pos.z, parts.lower)
	tx.set_block(above.x, above.y, above.z, parts.upper)
	broadcast_place_sound(mut tx, s, pos.x, pos.y, pos.z, parts.lower)
	broadcast_swing(mut tx, s)
	notify_block_changed(mut tx, pos)
	notify_block_changed(mut tx, above)
	return true
}
