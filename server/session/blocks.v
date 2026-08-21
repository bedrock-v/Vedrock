module session

import time
import protocol.version.v662.packets as packets_662
import protocol.version.v944.packets as packets_944
import protocol.version.v2168.packets as packets_2168
import protocol.version.v2168.types as types_2168
import protocol.version.v2168.enums as enums_2168
import protocol.types
import server.event
import server.world
import server.block
import server.item
import server.internal.network

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
	return s.player.game_mode() != network.game_type_spectator
		&& s.player.game_mode() != network.game_type_survival_spectator
		&& s.player.game_mode() != network.game_type_creative_spectator
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

// handle_inventory_transaction processes the standalone InventoryTransactionPacket.
fn (mut s NetworkSession) handle_inventory_transaction(p packets_2168.InventoryTransactionPacket) ! {
	match p.transaction_data {
		types_2168.UseItemTransactionData {
			pos := network.block_pos_from_v944(p.transaction_data.position)
			match p.transaction_data.action_type {
				.place {
					s.handle_place_click(pos, int(p.transaction_data.face), p.transaction_data.click_position[1])
				}
				.destroy {
					s.break_block(pos)!
				}
				.use {
					s.use_held_item_in_air()
				}
			}
		}
		types_2168.UseItemOnEntityTransactionData {
			match p.transaction_data.action_type {
				.attack {
					s.handle_attack(p.transaction_data.target_runtime_id)!
				}
				.interact, .item_interact {
					s.handle_entity_interact(p.transaction_data.target_runtime_id)
				}
			}
		}
		types_2168.NormalTransactionData, types_2168.MismatchTransactionData, types_2168.ReleaseItemTransactionData {
			// Crafting table slot moves (normal/mismatch) and charging item
			// release (bow draw, eat/drink finish) have no session side
			// handler yet.
		}
	}
}

fn (mut s NetworkSession) handle_player_auth_input(p packets_2168.PlayerAuthInputPacket) ! {
	on_ground := enums_2168.PlayerAuthInputData.vertical_collision in p.input_data
	s.update_movement(network.vec3_from_array(p.player_position), p.player_rotation[0],
		p.player_rotation[1], p.player_head_rotation, on_ground)
	if tx := p.item_use_transaction {
		s.handle_item_use_transaction(tx)!
	}
	if actions := p.player_block_actions {
		for action in actions {
			s.handle_player_block_action(action)!
		}
	}
}

fn (mut s NetworkSession) handle_item_use_transaction(tx types_2168.PackedItemUseLegacyInventoryTransaction) ! {
	pos := network.block_pos_from_v944(tx.position)
	match tx.action_type {
		.place {
			s.handle_place_click(pos, int(tx.face), tx.click_position[1])
		}
		.destroy {
			s.break_block(pos)!
		}
		.use {
			s.use_held_item_in_air()
		}
	}
}

fn (mut s NetworkSession) handle_place_click(block_position types.BlockPosition, block_face int, clicked_y f32) {
	if s.player.is_dead() || !s.can_interact() {
		s.log.debug('PLACE-DIAG: handle_place_click(${block_position.x},${block_position.y},${block_position.z}) dropped: dead=${s.player.is_dead()} can_interact=${s.can_interact()}')
		return
	}
	mut ictx := event.new_context(event.InteractData{
		player: s
		x:      block_position.x
		y:      block_position.y
		z:      block_position.z
		face:   block_face
	})
	s.hub.events.player_interact(mut ictx)
	if ictx.is_cancelled() {
		s.log.debug('PLACE-DIAG: handle_place_click(${block_position.x},${block_position.y},${block_position.z}) dropped: player_interact event cancelled')
		s.resend_block(block_position)
		return
	}
	// Neighbor cell in the clicked face direction. Used as the default
	// placement target and resent with the clicked block on rejection.
	neighbor := face_offset(block_position, block_face)
	clicked_id := s.block_at(block_position.x, block_position.y, block_position.z)
	if clicked_id == world.air.network_id || !s.within_place_reach(block_position) {
		s.log.debug('PLACE-DIAG: handle_place_click(${block_position.x},${block_position.y},${block_position.z}) dropped: clicked_id=${clicked_id} in_reach=${s.within_place_reach(block_position)} own_pos=${s.effective_position()}')
		s.resend_block(block_position)
		s.resend_block(neighbor)
		return
	}
	runtime_id := s.placement_runtime_id()
	binding := s.world_binding()
	if isnil(binding.world_runtime) {
		s.log.debug('PLACE-DIAG: handle_place_click(${block_position.x},${block_position.y},${block_position.z}) dropped: no bound world_runtime')
		return
	}
	mut wr := binding.world_runtime
	now := time.now().unix_milli()
	task := PlayerPlaceBlockTask{
		session_runtime_id: s.runtime_id
		epoch:              binding.epoch
		click_pos:          block_position
		click_face:         block_face
		clicked_y:          clicked_y
		runtime_id:         runtime_id
		yaw:                s.player.movement().yaw
		now_ms:             now
		last_place_ms:      s.last_place_ms
		is_creative:        s.player.game_mode() == network.game_type_creative
	}
	s.log.debug('PLACE-DIAG: handle_place_click(${block_position.x},${block_position.y},${block_position.z}) submitting PlayerPlaceBlockTask runtime_id=${runtime_id} face=${block_face} epoch=${binding.epoch}')
	if wr.submit(task) {
		placed := <-task.result
		s.log.debug('PLACE-DIAG: handle_place_click(${block_position.x},${block_position.y},${block_position.z}) PlayerPlaceBlockTask -> placed=${placed}')
		if placed {
			s.last_place_ms = now
		}
	} else {
		s.log.debug('PLACE-DIAG: handle_place_click(${block_position.x},${block_position.y},${block_position.z}) submit rejected (world stopping?)')
	}
}

// placement_runtime_id resolves the block to place from the server's own
// tracked held slot stack.
fn (s &NetworkSession) placement_runtime_id() int {
	stack, _ := s.inventory_stack_at(s.player.held_slot())
	if stack.count <= 0 || stack.id == 0 {
		s.log.debug('PLACE-DIAG: placement_runtime_id: held slot empty (count=${stack.count} id=${stack.id}), resolved to 0')
		return 0
	}
	if stack.block_runtime_id != 0 {
		s.log.debug('PLACE-DIAG: placement_runtime_id: held stack.block_runtime_id=${stack.block_runtime_id} (item id=${stack.id} meta=${stack.meta})')
		return stack.block_runtime_id
	}
	held_name := s.hub.data.item_name(stack.id)
	if held_item := s.hub.items.get(held_name) {
		resolved := held_item.block_runtime_id()
		s.log.debug('PLACE-DIAG: placement_runtime_id: resolved via item registry name=${held_name} -> ${resolved}')
		return resolved
	}
	s.log.debug('PLACE-DIAG: placement_runtime_id: held item name=${held_name} (id=${stack.id}) has no block_runtime_id and no registry entry, resolved to 0')
	return 0
}

// held_stack_and_name returns the currently held stack together with its
// namespaced item name, resolved once instead of at each held item call site.
fn (s &NetworkSession) held_stack_and_name() (types.ItemStack, string) {
	stack, _ := s.inventory_stack_at(s.player.held_slot())
	return stack, s.hub.data.item_name(stack.id)
}

// damage_held_item applies amount points of durability damage to the
// currently held item, removing it if it breaks. Creative mode tools never
// take durability damage.
fn (mut s NetworkSession) damage_held_item(amount int) {
	if s.player.game_mode() == network.game_type_creative
		|| s.player.game_mode() == network.game_type_creative_spectator {
		return
	}
	stack, net := s.inventory_stack_at(s.player.held_slot())
	if net == 0 {
		return
	}
	it := s.hub.items.get(s.hub.data.item_name(stack.id)) or { return }
	result := item.damage_item(it, stack.meta, amount)
	if result.broken {
		s.player.delete_stack(net)
		held_slot := s.player.held_slot()
		s.player.delete_slot(held_slot)
		s.player.set_held(held_slot, empty_stack())
		s.send_slot_update(held_slot, empty_stack())
		return
	}
	if result.new_meta == stack.meta {
		return
	}
	mut updated := stack
	updated.meta = result.new_meta
	s.player.put_stack(net, updated)
	wrapped := wrap_stack_id(updated, net)
	s.player.set_held(s.player.held_slot(), wrapped)
	s.send_slot_update(s.player.held_slot(), wrapped)
}

// use_held_item_in_air runs a UseableItem's on use behaviour (e.g. goat_horn's sound).
fn (mut s NetworkSession) use_held_item_in_air() {
	if s.player.is_dead() || !s.can_interact() {
		return
	}
	stack, name := s.held_stack_and_name()
	if cooldown := s.hub.items.cooldown_ticks(name) {
		if s.hub.current_tick() < s.cooldown_until[name] {
			return
		}
		s.cooldown_until[name] = s.hub.current_tick() + i64(cooldown)
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
	s.hub.broadcast(network.level_sound_event(result.sound, s.current_position(), -1,
		'minecraft:player', s.runtime_id))
}

fn (mut s NetworkSession) handle_player_action(p packets_944.PlayerActionPacket) ! {
	match p.action {
		.creative_destroy_block, .predict_destroy_block {
			s.break_block(network.block_pos_from_v944(p.block_position))!
		}
		.start_destroy_block {
			s.handle_start_break(network.block_pos_from_v944(p.block_position), int(p.face))
		}
		.continue_destroy_block {
			s.handle_continue_break(network.block_pos_from_v944(p.block_position), int(p.face))
		}
		.abort_destroy_block {
			s.handle_abort_break(network.block_pos_from_v944(p.block_position))
		}
		.respawn {
			s.request_respawn()
		}
		else {}
	}
}

fn (mut s NetworkSession) handle_player_block_action(action types_2168.PlayerBlockActionData) ! {
	pos := network.block_pos_from_v662(action.position)
	match action.action_type {
		.creative_destroy_block, .predict_destroy_block {
			s.break_block(pos)!
		}
		.start_destroy_block {
			s.handle_start_break(pos, int(action.facing))
		}
		.continue_destroy_block {
			s.handle_continue_break(pos, int(action.facing))
		}
		.abort_destroy_block {
			s.handle_abort_break(pos)
		}
		.respawn {
			s.request_respawn()
		}
		else {}
	}
}

// place_reach_sq returns the squared placement reach for the player's
// current gamemode.
fn (s &NetworkSession) place_reach_sq() f32 {
	if s.player.game_mode() == network.game_type_creative
		|| s.player.game_mode() == network.game_type_creative_spectator {
		return creative_place_reach_sq
	}
	return survival_place_reach_sq
}

// within_place_reach reports whether pos is within the player's current
// placement reach (see place_reach_sq), measured from the player's eyes.
// Uses effective_position (not player.position() directly) so a placement
// that immediately follows a movement update in the same packet batch is
// checked against where the client just said it is, not the position from
// before that movement was applied: see effective_position's own comment.
fn (s &NetworkSession) within_place_reach(pos types.BlockPosition) bool {
	own := s.effective_position()
	dx := f32(pos.x) + 0.5 - own.x
	dy := f32(pos.y) + 0.5 - own.y
	dz := f32(pos.z) + 0.5 - own.z
	return dx * dx + dy * dy + dz * dz <= s.place_reach_sq()
}

// resend_block sends the authoritative block state back to the client.
// It uses deliver because placement and break tasks may call it from the
// world thread.
fn (mut s NetworkSession) resend_block(pos types.BlockPosition) {
	s.deliver(&packets_944.UpdateBlockPacket{
		block_position:   network.block_pos_v944(pos)
		block_runtime_id: u32(s.block_at(pos.x, pos.y, pos.z))
		flags:            block_update_flags
		layer:            0
	})
}

// apply_consume_held_item mutates only this player's inventory through Player
// accessors and sends the slot update packet. World owned placement code calls
// it through WorldTx.consume_held_item.
fn (mut s NetworkSession) apply_consume_held_item() {
	stack, net := s.inventory_stack_at(s.player.held_slot())
	if net == 0 || stack.count <= 0 {
		return
	}
	item_name := s.hub.data.item_name(stack.id)
	mut ctx := event.new_context(event.ItemConsumeData{
		item_name: item_name
		player:    s
	})
	s.hub.events.item_consume(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	s.player.delete_stack(net)
	held_slot := s.player.held_slot()
	mut wrapped := empty_stack()
	if stack.count > 1 {
		mut remaining := stack
		remaining.count -= 1
		new_net := s.player.track_stack(remaining)
		s.player.set_slot(held_slot, new_net)
		wrapped = wrap_stack_id(remaining, new_net)
	} else {
		s.player.delete_slot(held_slot)
	}
	s.player.set_held(held_slot, wrapped)
	s.send_slot_update(held_slot, wrapped)
}

fn (mut s NetworkSession) break_block(pos types.BlockPosition) ! {
	if s.player.is_dead() || !s.can_interact() {
		s.log.debug('BREAK-DIAG: break_block(${pos.x},${pos.y},${pos.z}) dropped: dead=${s.player.is_dead()} can_interact=${s.can_interact()}')
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	air_id := world.air.network_id
	if old_id == air_id {
		s.log.debug('BREAK-DIAG: break_block(${pos.x},${pos.y},${pos.z}) dropped: block_at reports air')
		s.resend_block(pos)
		return
	}
	if !s.within_place_reach(pos) {
		s.log.debug('BREAK-DIAG: break_block(${pos.x},${pos.y},${pos.z}) dropped: out of reach, own_pos=${s.effective_position()}')
		s.resend_block(pos)
		return
	}
	if s.player.game_mode() != network.game_type_creative && !s.hub.blocks.breakable(old_id) {
		s.log.debug('BREAK-DIAG: break_block(${pos.x},${pos.y},${pos.z}) dropped: block id=${old_id} not breakable per hub.blocks')
		s.send_maybe_queued(&packets_944.UpdateBlockPacket{
			block_position:   network.block_pos_v944(pos)
			block_runtime_id: u32(old_id)
			flags:            block_update_flags
			layer:            0
		})!
		s.broadcast_cracking(network.level_event_stop_block_cracking, pos, 0)
		return
	}
	if s.player.game_mode() != network.game_type_creative && !s.break_complete(pos, old_id) {
		s.log.debug('BREAK-DIAG: break_block(${pos.x},${pos.y},${pos.z}) dropped: break_complete rejected id=${old_id}')
		s.resend_block(pos)
		s.broadcast_cracking(network.level_event_stop_block_cracking, pos, 0)
		return
	}
	s.set_breaking(none)
	binding := s.world_binding()
	if isnil(binding.world_runtime) {
		s.log.debug('BREAK-DIAG: break_block(${pos.x},${pos.y},${pos.z}) dropped: no bound world_runtime')
		return
	}
	mut wr := binding.world_runtime
	task := PlayerBreakBlockTask{
		session_runtime_id: s.runtime_id
		epoch:              binding.epoch
		x:                  pos.x
		y:                  pos.y
		z:                  pos.z
		old_id:             old_id
	}
	s.log.debug('BREAK-DIAG: break_block(${pos.x},${pos.y},${pos.z}) submitting PlayerBreakBlockTask old_id=${old_id} epoch=${binding.epoch}')
	if wr.submit(task) {
		_ := <-task.done
	} else {
		s.log.debug('BREAK-DIAG: break_block(${pos.x},${pos.y},${pos.z}) submit rejected (world stopping?)')
	}
}

// PlayerBreakBlockTask performs the validated break operation on the owning
// world actor. It is discarded if the block changed or the player switched worlds.
struct PlayerBreakBlockTask {
	session_runtime_id u64
	epoch              i64
	x                  int
	y                  int
	z                  int
	old_id             int
	done               chan bool = chan bool{cap: 1}
}

fn (t PlayerBreakBlockTask) name() string {
	return 'PlayerBreakBlockTask'
}

fn (t PlayerBreakBlockTask) run(mut tx WorldTx) {
	defer {
		t.done <- true
	}
	mut s := tx.player_for_epoch(t.session_runtime_id, t.epoch) or {
		eprintln('BREAK-DIAG: PlayerBreakBlockTask(${t.x},${t.y},${t.z}) dropped: player_for_epoch failed, session_runtime_id=${t.session_runtime_id} epoch=${t.epoch} (stale epoch/world switch?)')
		return
	}
	ok := tx.complete_block_break(mut s, types.BlockPosition{t.x, t.y, t.z}, t.old_id)
	s.log.debug('BREAK-DIAG: PlayerBreakBlockTask(${t.x},${t.y},${t.z}) complete_block_break -> ${ok}')
}

// complete_block_break destroys the block and runs everything that follows
// from it: the event, the drop, the container contents, the paired door half
// and the effects every player in the world sees.
//
// Both ways a block can be destroyed end up here. A client predicted destroy
// arrives as a PlayerBreakBlockTask, and a break the server itself finished
// calls in from tick_breaking, which is the only path that runs when the
// client has handed block breaking to the server.
fn (mut tx WorldTx) complete_block_break(mut s NetworkSession, pos types.BlockPosition, old_id int) bool {
	air_id := world.air.network_id
	current_id := tx.block_at(pos.x, pos.y, pos.z)
	if current_id != old_id {
		s.log.debug('BREAK-DIAG: complete_block_break(${pos.x},${pos.y},${pos.z}) dropped: expected id=${old_id} but tx.block_at now reports ${current_id} - block changed between session-thread capture and actor execution')
		s.resend_block(pos)
		return false
	}

	mut ctx := event.new_context(event.BlockBreakData{
		player:   s
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: old_id
	})
	tx.wr.events.block_break(mut ctx)
	if ctx.is_cancelled() {
		s.log.debug('BREAK-DIAG: complete_block_break(${pos.x},${pos.y},${pos.z}) dropped: block_break event cancelled')
		s.resend_block(pos)
		return false
	}

	tx.set_block(pos.x, pos.y, pos.z, air_id)
	tx.damage_held_item(mut s, 1)

	if s.player.game_mode() != network.game_type_creative && s.can_harvest(old_id) {
		drop_name, drop_count := block_drop_for(mut tx.wr, old_id)
		if drop_name != '' {
			center := types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5}
			spawn_dropped_item_stack(mut tx.wr, drop_name, drop_count, center)
		}
	}

	if b := tx.wr.hub.blocks.get(old_id) {
		if b is block.ChestBlock {
			drop_chest_contents(mut tx.wr, mut s, pos.x, pos.y, pos.z)
		}
	}

	if pair := tx.door_pair_pos(pos, old_id) {
		pair_id := tx.block_at(pair.x, pair.y, pair.z)
		if tx.door_pair_matches(old_id, pair_id) {
			tx.set_block(pair.x, pair.y, pair.z, air_id)
			tx.on_block_changed(pair.x, pair.y, pair.z)
			tx.recompute_neighbor_blocks(pair)
		}
	}

	tx.broadcast_stop_cracking(pos.x, pos.y, pos.z)
	tx.broadcast_destroy_particles(pos.x, pos.y, pos.z, old_id)
	tx.broadcast_swing(s)
	tx.on_block_changed(pos.x, pos.y, pos.z)
	tx.recompute_neighbor_blocks(pos)
	return true
}

// PlayerPlaceBlockTask handles one block interaction atomically on the
// owning world actor, avoiding races between branch selection and commit.
// Placement timing is captured by the session thread before submission.
struct PlayerPlaceBlockTask {
	session_runtime_id u64
	epoch              i64
	click_pos          types.BlockPosition
	click_face         int
	clicked_y          f32
	runtime_id         int
	yaw                f32
	now_ms             i64
	last_place_ms      i64
	is_creative        bool
	result             chan bool = chan bool{cap: 1}
}

fn (t PlayerPlaceBlockTask) name() string {
	return 'PlayerPlaceBlockTask'
}

fn (t PlayerPlaceBlockTask) run(mut tx WorldTx) {
	mut placed := false
	defer {
		t.result <- placed
	}
	mut s := tx.player_for_epoch(t.session_runtime_id, t.epoch) or {
		eprintln('PLACE-DIAG: PlayerPlaceBlockTask(${t.click_pos.x},${t.click_pos.y},${t.click_pos.z}) dropped: player_for_epoch failed, session_runtime_id=${t.session_runtime_id} epoch=${t.epoch} (stale epoch/world switch?)')
		return
	}
	pos := t.click_pos
	neighbor := face_offset(pos, t.click_face)
	clicked_id := tx.block_at(pos.x, pos.y, pos.z)

	if tx.interact_block(mut s, pos, clicked_id, t.click_face) {
		s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${pos.x},${pos.y},${pos.z}) short-circuited by interact_block (clicked_id=${clicked_id}) - no placement attempted')
		return
	}
	if tx.use_item_on_block(mut s, pos, clicked_id) {
		s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${pos.x},${pos.y},${pos.z}) short-circuited by use_item_on_block (clicked_id=${clicked_id}) - no placement attempted')
		return
	}
	if t.runtime_id == 0 {
		s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${pos.x},${pos.y},${pos.z}) dropped: runtime_id resolved to 0 at click time')
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	}

	mut target := pos
	if !tx.is_replaceable(clicked_id) {
		target = neighbor
	}
	dim := tx.world().dimension
	if target.y < dim.min_y || target.y > dim.max_y() {
		s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${pos.x},${pos.y},${pos.z}) dropped: target y=${target.y} out of world bounds')
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	}
	if t.now_ms - t.last_place_ms < place_cooldown_ms {
		s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${pos.x},${pos.y},${pos.z}) dropped: cooldown (${t.now_ms - t.last_place_ms}ms since last place)')
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	}

	if merged := tx.merged_slab(clicked_id, t.runtime_id, t.click_face, t.clicked_y, true) {
		placed = tx.replace_block_form(mut s, pos, merged)
		s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${pos.x},${pos.y},${pos.z}) merged_slab(on clicked) -> merged=${merged} placed=${placed}')
	} else if !tx.can_place_block_on_face(t.runtime_id, t.click_face, clicked_id) {
		s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${pos.x},${pos.y},${pos.z}) dropped: can_place_block_on_face rejected runtime_id=${t.runtime_id} face=${t.click_face} against clicked_id=${clicked_id}')
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	} else {
		placed_id := tx.oriented_block(t.runtime_id, t.click_face, t.clicked_y, t.yaw)
		target_id := tx.block_at(target.x, target.y, target.z)
		if merged2 := tx.merged_slab(target_id, t.runtime_id, t.click_face, t.clicked_y, false) {
			placed = tx.replace_block_form(mut s, target, merged2)
			s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${target.x},${target.y},${target.z}) merged_slab(on target) -> merged=${merged2} placed=${placed}')
		} else if parts := tx.door_placement(placed_id, target, t.click_face, t.yaw) {
			placed = tx.place_door_pair(mut s, target, parts)
			s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${target.x},${target.y},${target.z}) place_door_pair -> placed=${placed}')
		} else {
			placed = tx.place_block_form(mut s, target, placed_id)
			s.log.debug('PLACE-DIAG: PlayerPlaceBlockTask(${target.x},${target.y},${target.z}) place_block_form runtime_id=${t.runtime_id} oriented_id=${placed_id} -> placed=${placed} (post-place tx.block_at=${tx.block_at(target.x, target.y, target.z)})')
		}
	}

	if placed && !t.is_creative {
		tx.consume_held_item(mut s)
	}
}

// Block picking is session local: it reads the current world and updates the
// inventory through Player's state lock.
fn (mut s NetworkSession) handle_block_pick_request(p packets_662.BlockPickRequestPacket) ! {
	s.apply_block_pick_request(p)
}

fn (mut s NetworkSession) apply_block_pick_request(p packets_662.BlockPickRequestPacket) {
	pos := network.block_pos_from_v662(p.position)
	runtime_id := s.block_at(pos.x, pos.y, pos.z)
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
	if s.player.game_mode() != network.game_type_creative {
		return
	}

	stack := types.ItemStack{
		id:               item_id
		count:            1
		block_runtime_id: runtime_id
	}
	empty_slot := s.first_empty_slot() or {
		net_id := s.player.track_stack(stack)
		held_slot := s.player.held_slot()
		s.player.set_slot(held_slot, net_id)
		s.select_hotbar_slot(held_slot, wrap_stack_id(stack, net_id))
		return
	}
	if empty_slot < give_hotbar_size {
		net_id := s.player.track_stack(stack)
		s.player.set_slot(empty_slot, net_id)
		wrapped := wrap_stack_id(stack, net_id)
		s.send_slot_update(empty_slot, wrapped)
		s.select_hotbar_slot(empty_slot, wrapped)
		return
	}
	held, held_net := s.inventory_stack_at(s.player.held_slot())
	if held_net == 0 {
		s.player.delete_slot(empty_slot)
	} else {
		s.player.set_slot(empty_slot, held_net)
	}
	s.send_slot_update(empty_slot, wrap_stack_id(held, held_net))
	net_id := s.player.track_stack(stack)
	held_slot := s.player.held_slot()
	s.player.set_slot(held_slot, net_id)
	s.select_hotbar_slot(held_slot, wrap_stack_id(stack, net_id))
}

fn (s &NetworkSession) find_inventory_slot(item_id int, runtime_id int) ?int {
	for slot in 0 .. inventory_slot_count {
		net := s.player.inv_slot(slot) or { continue }
		existing := s.player.inv_stack(net) or { continue }
		if existing.id == item_id && existing.block_runtime_id == runtime_id {
			return slot
		}
	}
	return none
}

fn (mut s NetworkSession) swap_slot_into_hand(slot int) {
	picked, picked_net := s.inventory_stack_at(slot)
	held, held_net := s.inventory_stack_at(s.player.held_slot())
	if held_net == 0 {
		s.player.delete_slot(slot)
	} else {
		s.player.set_slot(slot, held_net)
	}
	s.send_slot_update(slot, wrap_stack_id(held, held_net))
	held_slot := s.player.held_slot()
	if picked_net == 0 {
		s.player.delete_slot(held_slot)
	} else {
		s.player.set_slot(held_slot, picked_net)
	}
	s.select_hotbar_slot(held_slot, wrap_stack_id(picked, picked_net))
}

fn (mut s NetworkSession) select_hotbar_slot(slot int, wrapped types.ItemStackWrapper) {
	s.player.set_held(slot, wrapped)
	s.send_maybe_queued(&packets_662.PlayerHotbarPacket{
		selected_slot:      u32(slot)
		container_id:       .inventory
		should_select_slot: true
	}) or {}
	s.hub.broadcast_except(s.runtime_id, &packets_2168.MobEquipmentPacket{
		target_runtime_id: network.actor_runtime_id(s.runtime_id)
		item:              network.item_descriptor_v2168_v2(wrapped.item_stack)
		slot:              i8(slot)
		selected_slot:     i8(slot)
		container_id:      .inventory
	})
}
