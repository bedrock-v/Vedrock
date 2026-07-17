module session

import time
import protocol
import protocol.types
import protocol.enums
import server.event
import server.world
import server.block
import server.item

// place_cooldown_ms throttles placement to at most one accepted block per
// window.
const place_cooldown_ms = i64(100)

const survival_place_reach_sq = f32(8.0 * 8.0)
const creative_place_reach_sq = f32(14.0 * 14.0)

// dimension returns the player's current world's dimension.
fn (s &NetworkSession) dimension() world.Dimension {
	wld := s.current_world()
	if isnil(wld) {
		return world.overworld
	}
	return wld.dimension
}

fn (s &NetworkSession) block_at(x int, y int, z int) int {
	wld, gen := s.world_and_generator()
	if !isnil(wld) {
		if id := wld.block_override(x, y, z) {
			return id
		}
	}
	return gen.block_at(x, y, z)
}

fn (s &NetworkSession) can_interact() bool {
	return s.game_mode != protocol.game_type_survival_spectator
		&& s.game_mode != protocol.game_type_creative_spectator
}

// is_replaceable reports whether block_id is silently overwritten by a
// placement rather than blocking it (short grass, ferns, etc.).
// see block.Replaceable.
fn (s &NetworkSession) is_replaceable(block_id int) bool {
	b := s.hub.blocks.get(block_id) or { return false }
	if b is block.Replaceable {
		return b.replaceable()
	}
	return false
}

fn face_offset(pos types.BlockPosition, face int) types.BlockPosition {
	return match face {
		0 { types.BlockPosition{pos.x, pos.y - 1, pos.z} }
		1 { types.BlockPosition{pos.x, pos.y + 1, pos.z} }
		2 { types.BlockPosition{pos.x, pos.y, pos.z - 1} }
		3 { types.BlockPosition{pos.x, pos.y, pos.z + 1} }
		4 { types.BlockPosition{pos.x - 1, pos.y, pos.z} }
		5 { types.BlockPosition{pos.x + 1, pos.y, pos.z} }
		else { pos }
	}
}

fn (mut s NetworkSession) handle_inventory_transaction(p protocol.InventoryTransactionPacket) ! {
	if p.transaction_type == protocol.inventory_transaction_type_use_item_on_entity {
		ue := p.use_item_on_entity
		if ue.action_type == protocol.item_use_on_entity_action_attack {
			s.handle_attack(ue.target_entity_runtime_id)!
		}
		return
	}
	if p.transaction_type != protocol.inventory_transaction_type_use_item {
		return
	}
	ut := p.use_item
	match ut.action_type {
		protocol.item_use_action_click_block {
			if s.dead || !s.can_interact() {
				return
			}
			mut ictx := event.new_context(event.InteractData{
				player: s
				x:      ut.block_position.x
				y:      ut.block_position.y
				z:      ut.block_position.z
				face:   int(ut.block_face)
			})
			s.hub.events.player_interact(mut ictx)
			if ictx.is_cancelled() {
				s.resend_block(ut.block_position)
				return
			}
			// Neighbor cell in the clicked face direction. Used as the default
			// placement target and resent with the clicked block on rejection.
			neighbor := face_offset(ut.block_position, int(ut.block_face))
			clicked_id := s.block_at(ut.block_position.x, ut.block_position.y, ut.block_position.z)
			if clicked_id == world.air.network_id || !s.within_place_reach(ut.block_position) {
				s.resend_block(ut.block_position)
				s.resend_block(neighbor)
				return
			}
			if s.interact_block(ut.block_position, clicked_id, int(ut.block_face))! {
				return
			}
			if s.use_item_on_block(ut.block_position, clicked_id) {
				return
			}
			runtime_id := ut.held_item.item_stack.block_runtime_id
			if runtime_id == 0 {
				return
			}
			mut target := ut.block_position
			if !s.is_replaceable(clicked_id) {
				target = neighbor
			}
			dim := s.dimension()
			if target.y < dim.min_y || target.y > dim.max_y() {
				s.resend_block(ut.block_position)
				s.resend_block(neighbor)
				return
			}
			now := time.now().unix_milli()
			if now - s.last_place_ms < place_cooldown_ms {
				s.resend_block(ut.block_position)
				s.resend_block(neighbor)
				return
			}
			if merged := s.merged_slab(clicked_id, runtime_id, int(ut.block_face),
				ut.clicked_position.y, true)
			{
				if s.replace_block(ut.block_position, merged)! {
					s.last_place_ms = now
					if s.game_mode != protocol.game_type_creative {
						s.consume_held_item()
					}
				}
				return
			}
			if !s.can_place_block_on_face(runtime_id, int(ut.block_face), clicked_id) {
				s.resend_block(ut.block_position)
				s.resend_block(neighbor)
				return
			}
			placed_id := s.oriented_block(runtime_id, int(ut.block_face), ut.clicked_position.y)
			target_id := s.block_at(target.x, target.y, target.z)
			if merged := s.merged_slab(target_id, runtime_id, int(ut.block_face),
				ut.clicked_position.y, false)
			{
				if s.replace_block(target, merged)! {
					s.last_place_ms = now
					if s.game_mode != protocol.game_type_creative {
						s.consume_held_item()
					}
				}
				return
			}
			if parts := s.door_placement(placed_id, target, int(ut.block_face)) {
				if s.place_door(target, parts)! {
					s.last_place_ms = now
					if s.game_mode != protocol.game_type_creative {
						s.consume_held_item()
					}
				}
				return
			}
			if s.place_block(target, placed_id)! {
				s.last_place_ms = now
				if s.game_mode != protocol.game_type_creative {
					s.consume_held_item()
				}
			}
		}
		protocol.item_use_action_destroy_block {
			s.break_block(ut.block_position)!
		}
		protocol.item_use_action_click_air {
			s.use_held_item_in_air()
		}
		else {}
	}
}

// held_stack_and_name returns the currently held stack together with its
// namespaced item name, resolved once instead of at each held- tem call site.
fn (s &NetworkSession) held_stack_and_name() (types.ItemStack, string) {
	stack, _ := s.inventory_stack_at(s.held_slot)
	return stack, s.hub.data.item_name(stack.id)
}

// use_item_on_block applies the held item's UsableOnBlockItem effect (e.g.
// bone meal advancing a crop's growth stage) if clicked_id qualifies.
// Returns false for every item/block combination that doesn't. Callers
// should then fall through to ordinary placement handling.
fn (mut s NetworkSession) use_item_on_block(pos types.BlockPosition, clicked_id int) bool {
	if isnil(s.hub.palette) {
		return false
	}
	v := s.hub.palette.variant(clicked_id) or { return false }
	stack, name := s.held_stack_and_name()
	result := s.hub.items.use_on_block_result(name, v.name, stack.meta) or { return false }
	current := v.states[result.state_key] or { return false }.int()
	new_id := s.hub.palette.with_state(clicked_id, result.state_key,
		(current + result.state_delta).str()) or { return false }
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
	s.write_block_runtime(pos, new_id)
	s.broadcast_block_update(pos, new_id)
	if result.sound != '' {
		s.hub.broadcast(&protocol.LevelSoundEventPacket{
			sound:           result.sound
			position:        s.current_position()
			extra_data:      -1
			entity_type:     'minecraft:player'
			actor_unique_id: i64(s.runtime_id)
		})
	}
	s.broadcast_swing()
	if s.game_mode != protocol.game_type_creative {
		s.consume_held_item()
	}
	s.after_block_changed(pos)
	return true
}

// damage_held_item applies amount points of durability damage to the
// currently held item, removing it if it breaks. Creative mode tools never
// take durability damage.
fn (mut s NetworkSession) damage_held_item(amount int) {
	if s.game_mode == protocol.game_type_creative
		|| s.game_mode == protocol.game_type_creative_spectator {
		return
	}
	stack, net := s.inventory_stack_at(s.held_slot)
	if net == 0 {
		return
	}
	it := s.hub.items.get(s.hub.data.item_name(stack.id)) or { return }
	result := item.damage_item(it, stack.meta, amount)
	if result.broken {
		s.inv_stacks.delete(net)
		s.inv_slots.delete(s.held_slot)
		s.held_item = empty_stack()
		s.send_slot_update(s.held_slot, empty_stack())
		return
	}
	if result.new_meta == stack.meta {
		return
	}
	mut updated := stack
	updated.meta = result.new_meta
	s.inv_stacks[net] = updated
	s.held_item = wrap_stack_id(updated, net)
	s.send_slot_update(s.held_slot, s.held_item)
}

// use_held_item_in_air runs a UseableItem's on use behaviour (e.g. goat_horn's sound).
fn (mut s NetworkSession) use_held_item_in_air() {
	if s.dead || !s.can_interact() {
		return
	}
	stack, name := s.held_stack_and_name()
	if cooldown := s.hub.items.cooldown_ticks(name) {
		if s.hub.current_tick < s.cooldown_until[name] {
			return
		}
		s.cooldown_until[name] = s.hub.current_tick + i64(cooldown)
	}
	result := s.hub.items.use_result(name, stack.meta) or { return }
	mut use_ctx := event.new_context(event.ItemUseData{
		player:    s
		item_name: name
		meta:      stack.meta
	})
	s.hub.events.item_use(mut use_ctx)
	if use_ctx.is_cancelled() {
		return
	}
	if result.sound == '' {
		return
	}
	s.hub.broadcast(&protocol.LevelSoundEventPacket{
		sound:           result.sound
		position:        s.current_position()
		extra_data:      -1
		entity_type:     'minecraft:player'
		actor_unique_id: i64(s.runtime_id)
	})
}

fn (mut s NetworkSession) handle_player_action(p protocol.PlayerActionPacket) ! {
	match p.action {
		int(enums.PlayerAction.creative_player_destroy_block),
		int(enums.PlayerAction.predict_destroy_block) {
			s.break_block(p.block_position)!
		}
		int(enums.PlayerAction.start_break) {
			s.handle_start_break(p.block_position, p.face)
		}
		int(enums.PlayerAction.respawn) {
			s.respawn()
		}
		else {}
	}
}

fn (mut s NetworkSession) handle_start_break(pos types.BlockPosition, click_face int) {
	if s.dead || !s.can_interact() {
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	if old_id == world.air.network_id {
		return
	}
	mut ctx := event.new_context(event.StartBreakData{
		player: s
		x:      pos.x
		y:      pos.y
		z:      pos.z
		face:   click_face
	})
	s.hub.events.start_break(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return
	}
	if punchable := s.hub.blocks.get(old_id) {
		if punchable is block.Punchable {
			mut wld := s.current_world()
			if !isnil(wld) {
				punchable.punch(pos.x, pos.y, pos.z, click_face, mut wld)
			}
		}
	}
	s.broadcast_swing()
}

// place_reach_sq returns the squared placement reach for the player's
// current gamemode.
fn (s &NetworkSession) place_reach_sq() f32 {
	if s.game_mode == protocol.game_type_creative
		|| s.game_mode == protocol.game_type_creative_spectator {
		return creative_place_reach_sq
	}
	return survival_place_reach_sq
}

// within_place_reach reports whether pos is within the player's current
// placement reach (see place_reach_sq), measured from the player's eyes.
fn (s &NetworkSession) within_place_reach(pos types.BlockPosition) bool {
	dx := f32(pos.x) + 0.5 - s.position.x
	dy := f32(pos.y) + 0.5 - s.position.y
	dz := f32(pos.z) + 0.5 - s.position.z
	return dx * dx + dy * dy + dz * dz <= s.place_reach_sq()
}

fn (mut s NetworkSession) resend_block(pos types.BlockPosition) {
	s.transport.send(&protocol.UpdateBlockPacket{
		block_position:   pos
		block_runtime_id: s.block_at(pos.x, pos.y, pos.z)
		flags:            block_update_flags
		data_layer_id:    0
	}) or {}
}

// oriented_block resolves a directional block's runtime id from the player's
// yaw and the clicked face. Falls back to the raw id when no palette is loaded.
fn (s &NetworkSession) oriented_block(runtime_id int, click_face int, click_y f32) int {
	if isnil(s.hub.palette) {
		return runtime_id
	}
	return s.hub.palette.oriented(runtime_id, s.yaw, click_face, click_y)
}

fn (s &NetworkSession) can_place_block_on_face(runtime_id int, click_face int, support_id int) bool {
	if isnil(s.hub.palette) {
		return true
	}
	return s.hub.palette.can_place_on_support(runtime_id, click_face, support_id)
}

fn (s &NetworkSession) merged_slab(existing_id int, placing_id int, click_face int, click_y f32, clicked bool) ?int {
	if existing_id == world.air.network_id || isnil(s.hub.palette) {
		return none
	}
	return s.hub.palette.merged_slab(existing_id, placing_id, click_face, click_y, clicked)
}

fn (s &NetworkSession) door_placement(runtime_id int, pos types.BlockPosition, click_face int) ?world.DoorPlacement {
	if click_face != 1 || isnil(s.hub.palette) {
		return none
	}
	above := face_offset(pos, 1)
	below := face_offset(pos, 0)
	dim := s.dimension()
	if pos.y < dim.min_y || above.y > dim.max_y() {
		return none
	}
	if s.block_at(pos.x, pos.y, pos.z) != world.air.network_id
		|| s.block_at(above.x, above.y, above.z) != world.air.network_id {
		return none
	}
	below_id := s.block_at(below.x, below.y, below.z)
	if !s.hub.palette.model(below_id).face_solid(1) {
		return none
	}
	return s.hub.palette.door_placement(runtime_id, s.yaw, s.neighbor_ids(pos))
}

fn (mut s NetworkSession) place_block(pos types.BlockPosition, runtime_id int) !bool {
	occupied := s.block_at(pos.x, pos.y, pos.z) != world.air.network_id
	obstructed, self_only := s.obstructed_by_entity(pos)
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
	s.hub.events.block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return false
	}
	s.write_block_runtime(pos, runtime_id)
	s.broadcast_block_update(pos, runtime_id)
	s.broadcast_swing()
	s.after_block_changed(pos)
	return true
}

fn (mut s NetworkSession) replace_block(pos types.BlockPosition, runtime_id int) !bool {
	mut ctx := event.new_context(event.BlockPlaceData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: runtime_id
	})
	s.hub.events.block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return false
	}
	s.set_block_runtime(pos, runtime_id)
	s.broadcast_swing()
	s.after_block_changed(pos)
	return true
}

fn (mut s NetworkSession) place_door(pos types.BlockPosition, parts world.DoorPlacement) !bool {
	above := face_offset(pos, 1)
	obstructed_lower, lower_self := s.obstructed_by_entity(pos)
	obstructed_upper, upper_self := s.obstructed_by_entity(above)
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
	s.hub.events.block_place(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		s.resend_block(above)
		return false
	}
	s.write_block_runtime(pos, parts.lower)
	s.write_block_runtime(above, parts.upper)
	s.broadcast_block_update(pos, parts.lower)
	s.broadcast_block_update(above, parts.upper)
	s.broadcast_swing()
	s.after_block_changed(pos)
	s.after_block_changed(above)
	return true
}

fn (mut s NetworkSession) consume_held_item() {
	stack, net := s.inventory_stack_at(s.held_slot)
	if net == 0 || stack.count <= 0 {
		return
	}
	s.inv_stacks.delete(net)
	mut wrapped := empty_stack()
	if stack.count > 1 {
		mut remaining := stack
		remaining.count -= 1
		new_net := s.track_stack(remaining)
		s.inv_slots[s.held_slot] = new_net
		wrapped = wrap_stack_id(remaining, new_net)
	} else {
		s.inv_slots.delete(s.held_slot)
	}
	s.held_item = wrapped
	s.send_slot_update(s.held_slot, wrapped)
}

// obstructed_by_entity reports whether pos overlaps any connected player's
// actual bounding box (0.6 wide, 1.8 tall | player_half_width/player_height),
// including the placing player themself. Vedrock has no other entity types
// yet, so checking all sessions covers every entity that currently exists.
fn (mut s NetworkSession) obstructed_by_entity(pos types.BlockPosition) (bool, bool) {
	block_min_x := f32(pos.x)
	block_max_x := f32(pos.x) + 1
	block_min_y := f32(pos.y)
	block_max_y := f32(pos.y) + 1
	block_min_z := f32(pos.z)
	block_max_z := f32(pos.z) + 1
	mut obstructed := false
	for mut target in s.hub.snapshot() {
		// Read cross-session position under the target's pos_mutex - it is
		// written on that session's own thread.
		tp := target.current_position()
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
		if target.runtime_id == s.runtime_id {
			continue
		}
		return true, false
	}
	return obstructed, true
}

fn (mut s NetworkSession) break_block(pos types.BlockPosition) ! {
	old_id := s.block_at(pos.x, pos.y, pos.z)
	air_id := world.air.network_id
	if old_id == air_id {
		return
	}
	if s.game_mode != protocol.game_type_creative && !s.hub.blocks.breakable(old_id) {
		s.transport.send(&protocol.UpdateBlockPacket{
			block_position:   pos
			block_runtime_id: old_id
			flags:            block_update_flags
			data_layer_id:    0
		})!
		return
	}
	mut ctx := event.new_context(event.BlockBreakData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: old_id
	})
	s.hub.events.block_break(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return
	}
	s.write_block_runtime(pos, air_id)
	s.broadcast_block_update(pos, air_id)
	s.damage_held_item(1)
	if pair := s.door_pair_pos(pos, old_id) {
		pair_id := s.block_at(pair.x, pair.y, pair.z)
		if s.door_pair_matches(old_id, pair_id) {
			s.write_block_runtime(pair, air_id)
			s.broadcast_block_update(pair, air_id)
			s.after_block_changed(pair)
		}
	}
	s.broadcast_destroy_particles(pos, old_id)
	s.broadcast_swing()
	s.after_block_changed(pos)
}

fn (mut s NetworkSession) interact_block(pos types.BlockPosition, old_id int, click_face int) !bool {
	if isnil(s.hub.palette) {
		return false
	}
	if new_id := s.carve_pumpkin(old_id, click_face) {
		s.set_block_runtime(pos, new_id)
		s.broadcast_swing()
		s.after_block_changed(pos)
		return true
	}
	if pair := s.door_pair_pos(pos, old_id) {
		pair_id := s.block_at(pair.x, pair.y, pair.z)
		if toggled := s.hub.palette.door_toggled_pair(old_id, pair_id) {
			s.write_block_runtime(pos, toggled.clicked)
			s.write_block_runtime(pair, toggled.pair)
			s.broadcast_block_update(pos, toggled.clicked)
			s.broadcast_block_update(pair, toggled.pair)
			s.broadcast_swing()
			s.after_block_changed(pair)
			s.after_block_changed(pos)
			return true
		}
		return false
	}
	if new_id := s.hub.palette.toggled_open(old_id) {
		s.set_block_runtime(pos, new_id)
		s.broadcast_swing()
		s.after_block_changed(pos)
		return true
	}
	interactable := s.hub.blocks.get(old_id) or { return false }
	if interactable is block.Interactable {
		mut wld := s.current_world()
		if isnil(wld) {
			return false
		}
		if !interactable.interact(pos.x, pos.y, pos.z, click_face, mut wld) {
			return false
		}
		s.broadcast_block_update(pos, s.block_at(pos.x, pos.y, pos.z))
		s.broadcast_swing()
		s.after_block_changed(pos)
		return true
	}
	return false
}

fn (mut s NetworkSession) carve_pumpkin(old_id int, click_face int) ?int {
	_, name := s.held_stack_and_name()
	if name != 'minecraft:shears' {
		return none
	}
	return s.hub.palette.carved_pumpkin_id(old_id, click_face)
}

fn (s &NetworkSession) door_pair_pos(pos types.BlockPosition, id int) ?types.BlockPosition {
	if isnil(s.hub.palette) {
		return none
	}
	_ := s.hub.palette.door_pair_id(id) or { return none }
	if s.hub.palette.is_door_top(id) {
		return face_offset(pos, 0)
	}
	return face_offset(pos, 1)
}

fn (s &NetworkSession) door_pair_matches(id int, pair_id int) bool {
	if isnil(s.hub.palette) {
		return false
	}
	expected := s.hub.palette.door_pair_id(id) or { return false }
	return expected == pair_id
}

fn (mut s NetworkSession) set_block_runtime(pos types.BlockPosition, runtime_id int) {
	s.write_block_runtime(pos, runtime_id)
	s.broadcast_block_update(pos, runtime_id)
}

// PlayerBlockWriteJob is an ordinary (player) block write as a WorldJob.
// The same actor thread landing point SetBlockJob (blocks_api.v) already gives
// the plugin/command path, so a player placing/breaking a block is
// serialized against scheduled ticks/liquid spread/arena restores touching
// the same cell instead of writing directly on the connection thread.
struct PlayerBlockWriteJob {
	session_runtime_id u64
	x                  int
	y                  int
	z                  int
	block_id           int
}

fn (j PlayerBlockWriteJob) run(mut h Hub) {
	mut owner := h.session_by_runtime(j.session_runtime_id) or { return }
	mut wld := owner.current_world()
	if !isnil(wld) {
		wld.set_block(j.x, j.y, j.z, j.block_id)
	}
}

fn (mut s NetworkSession) write_block_runtime(pos types.BlockPosition, runtime_id int) {
	s.hub.submit(PlayerBlockWriteJob{
		session_runtime_id: s.runtime_id
		x:                  pos.x
		y:                  pos.y
		z:                  pos.z
		block_id:           runtime_id
	})
}

fn (mut s NetworkSession) after_block_changed(pos types.BlockPosition) {
	s.hub.on_block_changed(pos.x, pos.y, pos.z)
	s.recompute_neighbor_blocks(pos)
}

fn (mut s NetworkSession) recompute_neighbor_blocks(pos types.BlockPosition) {
	if isnil(s.hub.palette) {
		return
	}
	for p in [
		pos,
		face_offset(pos, 2),
		face_offset(pos, 3),
		face_offset(pos, 4),
		face_offset(pos, 5),
	] {
		old_id := s.block_at(p.x, p.y, p.z)
		if old_id == world.air.network_id {
			continue
		}
		new_id := s.hub.palette.connected_block(old_id, s.neighbor_ids(p))
		if new_id != old_id {
			s.set_block_runtime(p, new_id)
		}
	}
}

fn (s &NetworkSession) neighbor_ids(pos types.BlockPosition) world.NeighborBlockIDs {
	return world.NeighborBlockIDs{
		north: s.block_at(pos.x, pos.y, pos.z - 1)
		east:  s.block_at(pos.x + 1, pos.y, pos.z)
		south: s.block_at(pos.x, pos.y, pos.z + 1)
		west:  s.block_at(pos.x - 1, pos.y, pos.z)
		above: s.block_at(pos.x, pos.y + 1, pos.z)
		below: s.block_at(pos.x, pos.y - 1, pos.z)
	}
}

fn (mut s NetworkSession) broadcast_destroy_particles(pos types.BlockPosition, runtime_id int) {
	s.hub.broadcast(&protocol.LevelEventPacket{
		event_id:   protocol.level_event_particles_destroy_block
		position:   types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5}
		event_data: runtime_id
	})
}

fn (mut s NetworkSession) broadcast_block_update(pos types.BlockPosition, runtime_id int) {
	s.hub.broadcast(&protocol.UpdateBlockPacket{
		block_position:   pos
		block_runtime_id: runtime_id
		flags:            block_update_flags
		data_layer_id:    0
	})
}

fn (mut s NetworkSession) broadcast_swing() {
	s.hub.broadcast_except(s.runtime_id, &protocol.AnimatePacket{
		action:           protocol.animate_action_swing_arm
		actor_runtime_id: s.runtime_id
	})
}

fn (mut s NetworkSession) handle_block_pick_request(p protocol.BlockPickRequestPacket) ! {
	runtime_id := s.block_at(p.block_position.x, p.block_position.y, p.block_position.z)
	if runtime_id == world.air.network_id {
		return
	}
	item_id := s.hub.data.item_for_block(runtime_id)
	if item_id == 0 {
		return
	}

	if existing_slot := s.find_inventory_slot(item_id, runtime_id) {
		if existing_slot < give_hotbar_size {
			stack, net := s.inventory_stack_at(existing_slot)
			s.select_hotbar_slot(existing_slot, wrap_stack_id(stack, net))
		} else {
			s.swap_slot_into_hand(existing_slot)
		}
		return
	}
	if s.game_mode != protocol.game_type_creative {
		return
	}

	stack := types.ItemStack{
		id:               item_id
		count:            1
		block_runtime_id: runtime_id
	}
	empty_slot := s.first_empty_slot() or {
		net_id := s.track_stack(stack)
		s.inv_slots[s.held_slot] = net_id
		s.select_hotbar_slot(s.held_slot, wrap_stack_id(stack, net_id))
		return
	}
	if empty_slot < give_hotbar_size {
		net_id := s.track_stack(stack)
		s.inv_slots[empty_slot] = net_id
		wrapped := wrap_stack_id(stack, net_id)
		s.send_slot_update(empty_slot, wrapped)
		s.select_hotbar_slot(empty_slot, wrapped)
		return
	}
	held, held_net := s.inventory_stack_at(s.held_slot)
	if held_net == 0 {
		s.inv_slots.delete(empty_slot)
	} else {
		s.inv_slots[empty_slot] = held_net
	}
	s.send_slot_update(empty_slot, wrap_stack_id(held, held_net))
	net_id := s.track_stack(stack)
	s.inv_slots[s.held_slot] = net_id
	s.select_hotbar_slot(s.held_slot, wrap_stack_id(stack, net_id))
}

fn (s &NetworkSession) find_inventory_slot(item_id int, runtime_id int) ?int {
	for slot in 0 .. inventory_slot_count {
		net := s.inv_slots[slot] or { continue }
		existing := s.inv_stacks[net] or { continue }
		if existing.id == item_id && existing.block_runtime_id == runtime_id {
			return slot
		}
	}
	return none
}

fn (mut s NetworkSession) swap_slot_into_hand(slot int) {
	picked, picked_net := s.inventory_stack_at(slot)
	held, held_net := s.inventory_stack_at(s.held_slot)
	if held_net == 0 {
		s.inv_slots.delete(slot)
	} else {
		s.inv_slots[slot] = held_net
	}
	s.send_slot_update(slot, wrap_stack_id(held, held_net))
	if picked_net == 0 {
		s.inv_slots.delete(s.held_slot)
	} else {
		s.inv_slots[s.held_slot] = picked_net
	}
	s.select_hotbar_slot(s.held_slot, wrap_stack_id(picked, picked_net))
}

fn (mut s NetworkSession) select_hotbar_slot(slot int, wrapped types.ItemStackWrapper) {
	s.held_item = wrapped
	s.held_slot = slot
	s.transport.send(&protocol.PlayerHotbarPacket{
		selected_hotbar_slot: slot
		window_id:            inventory_window_id
		select_hotbar_slot:   true
	}) or {}
	s.hub.broadcast_except(s.runtime_id, &protocol.MobEquipmentPacket{
		actor_runtime_id: s.runtime_id
		item:             wrapped
		inventory_slot:   slot
		hotbar_slot:      slot
		window_id:        inventory_window_id
	})
}
