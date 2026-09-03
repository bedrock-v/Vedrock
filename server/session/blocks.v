module session

import time
import bedrock_v.protocol.types
import server.event
import server.world
import server.block
import server.item
import bedrock_v.protocol.current as proto
import server.player
import server.worldrt

// place_cooldown_ms throttles placement to at most one accepted block per
// window.
const place_cooldown_ms = i64(100)

const survival_place_reach_sq = f32(8.0 * 8.0)
const creative_place_reach_sq = f32(14.0 * 14.0)

// max_block_actions_per_input bounds the block actions one PlayerAuthInput may
// carry. Each action can start or finish a break and reaches the owning world's
// actor thread, so an unbounded list is work a single packet can force on every
// player in that world. The vanilla client sends a couple per tick.
const max_block_actions_per_input = 64

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
	binding := s.world_binding()
	if !isnil(binding.world_runtime) {
		mut wr := binding.world_runtime
		return wr.generated_block(x, y, z)
	}
	return gen.block_at(x, y, z)
}

fn (s &NetworkSession) can_interact() bool {
	return s.player.game_mode() != .spectator
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

// handle_inventory_transaction processes the standalone
// InventoryTransactionPacket. A click on a block arrives here rather than in
// PlayerAuthInput, which carries the same body but only for some of the ways
// the client reports one.
fn (mut s NetworkSession) handle_inventory_transaction(p proto.InventoryTransactionPacket) ! {
	use_item := p.use_item or { return }
	s.handle_item_use(use_item.action_type, proto.block_pos_from(use_item.position),
		int(use_item.face), use_item.click_position[1])!
}

fn (mut s NetworkSession) handle_player_auth_input(p proto.PlayerAuthInputPacket) ! {
	on_ground := proto.PlayerAuthInputData.vertical_collision in p.input_data
	s.update_movement(proto.vec3_from_array(p.player_position), p.player_rotation[0],
		p.player_rotation[1], p.player_head_rotation, on_ground)
	if tx := p.item_use_transaction {
		s.handle_item_use_transaction(tx)!
	}
	if actions := p.player_block_actions {
		if actions.len > max_block_actions_per_input {
			return error('player auth input carried ${actions.len} block actions')
		}
		for action in actions {
			s.handle_player_block_action(action)!
		}
	}
}

fn (mut s NetworkSession) handle_item_use_transaction(tx proto.PackedItemUseLegacyInventoryTransaction) ! {
	s.handle_item_use(tx.action_type, proto.block_pos_from(tx.position), int(tx.face),
		tx.click_position[1])!
}

// handle_item_use runs one click on a block. Both transports of the same body
// end here, so a click means the same thing whichever the client used.
fn (mut s NetworkSession) handle_item_use(action proto.ItemUseInventoryTransactionType, pos types.BlockPosition, face int, clicked_y f32) ! {
	match action {
		.place {
			s.handle_place_click(pos, face, clicked_y)
		}
		.destroy {
			s.break_block(pos)!
		}
		.use {
			s.use_held_item_in_air()
		}
		else {
			// The alias keeps V from seeing the enum as exhaustive; a value
			// outside the three the game defines is not a click at all.
		}
	}
}

fn (mut s NetworkSession) handle_place_click(block_position types.BlockPosition, block_face int, clicked_y f32) {
	if s.player.is_dead() || !s.can_interact() {
		return
	}
	mut ictx := event.new_context(player.InteractData{
		player: s.player
		x:      block_position.x
		y:      block_position.y
		z:      block_position.z
		face:   block_face
	})
	s.player.handler.on_player_interact(mut ictx)
	if ictx.is_cancelled() {
		s.resend_block(block_position)
		return
	}
	// Neighbor cell in the clicked face direction. Used as the default
	// placement target and resent with the clicked block on rejection.
	neighbor := face_offset(block_position, block_face)
	clicked_id := s.block_at(block_position.x, block_position.y, block_position.z)
	if clicked_id == world.air.network_id || !s.within_place_reach(block_position) {
		s.resend_block(block_position)
		s.resend_block(neighbor)
		return
	}
	runtime_id := s.placement_runtime_id()
	binding := s.world_binding()
	if isnil(binding.world_runtime) {
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
		is_creative:        s.player.game_mode() == .creative
	}
	if wr.submit(task) {
		placed := <-task.result
		if placed {
			s.last_place_ms = now
		}
	}
}

// placement_runtime_id resolves the block to place from the server's own
// tracked held slot stack.
fn (s &NetworkSession) placement_runtime_id() int {
	stack, _ := s.inventory_stack_at(s.player.held_slot())
	if stack.count <= 0 || stack.id == 0 {
		return 0
	}
	if stack.block_runtime_id != 0 {
		return stack.block_runtime_id
	}
	held_name := s.hub.data.item_name(stack.id)
	if held_item := item.get(held_name) {
		return held_item.block_runtime_id()
	}
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
	if s.player.game_mode() == .creative {
		return
	}
	stack, net := s.inventory_stack_at(s.player.held_slot())
	if net == 0 {
		return
	}
	it := item.get(s.hub.data.item_name(stack.id)) or { return }
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
	if cooldown := item.cooldown_ticks(name) {
		if s.hub.current_tick() < s.cooldown_until[name] {
			return
		}
		s.cooldown_until[name] = s.hub.current_tick() + i64(cooldown)
	}
	result := item.use_result(name, stack.meta) or { return }
	mut use_ctx := event.new_context(player.ItemUseData{
		player:    s.player
		item_name: name
		meta:      stack.meta
	})
	s.player.handler.on_item_use(mut use_ctx)
	if use_ctx.is_cancelled() {
		return
	}
	if result.sound == '' {
		return
	}
	s.hub.broadcast(proto.level_sound_event(result.sound, s.current_position(), -1,
		'minecraft:player', s.runtime_id))
}

fn (mut s NetworkSession) handle_player_action(p proto.PlayerActionPacket) ! {
	match p.action {
		.creative_destroy_block, .predict_destroy_block {
			s.break_block(proto.block_pos_from(p.block_position))!
		}
		.start_destroy_block {
			s.handle_start_break(proto.block_pos_from(p.block_position), int(p.face))
		}
		.continue_destroy_block {
			s.handle_continue_break(proto.block_pos_from(p.block_position), int(p.face))
		}
		.abort_destroy_block {
			s.handle_abort_break(proto.block_pos_from(p.block_position))
		}
		.respawn {
			s.request_respawn()
		}
		else {}
	}
}

fn (mut s NetworkSession) handle_player_block_action(action proto.PlayerBlockActionData) ! {
	pos := proto.block_pos_from_legacy(action.position)
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
	if s.player.game_mode() == .creative {
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
	s.deliver(&proto.UpdateBlockPacket{
		block_position:   proto.block_pos(pos)
		block_runtime_id: u32(s.block_at(pos.x, pos.y, pos.z))
		flags:            worldrt.block_update_flags
		layer:            0
	})
}

// apply_consume_held_item mutates only this player's inventory through Player
// accessors and sends the slot update packet. World owned placement code calls
// it through worldrt.WorldTx.consume_held_item.
fn (mut s NetworkSession) apply_consume_held_item() {
	stack, net := s.inventory_stack_at(s.player.held_slot())
	if net == 0 || stack.count <= 0 {
		return
	}
	item_name := s.hub.data.item_name(stack.id)
	mut ctx := event.new_context(player.ItemConsumeData{
		item_name: item_name
		player:    s.player
	})
	s.player.handler.on_item_consume(mut ctx)
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
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	air_id := world.air.network_id
	if old_id == air_id {
		s.resend_block(pos)
		return
	}
	if !s.within_place_reach(pos) {
		s.resend_block(pos)
		return
	}
	if s.player.game_mode() != .creative && !block.breakable(old_id) {
		s.send_maybe_queued(&proto.UpdateBlockPacket{
			block_position:   proto.block_pos(pos)
			block_runtime_id: u32(old_id)
			flags:            worldrt.block_update_flags
			layer:            0
		})!
		s.broadcast_cracking(proto.level_event_stop_block_cracking, pos, 0)
		return
	}
	if s.player.game_mode() != .creative && !s.break_complete(pos, old_id) {
		s.resend_block(pos)
		s.broadcast_cracking(proto.level_event_stop_block_cracking, pos, 0)
		return
	}
	s.set_breaking(none)
	binding := s.world_binding()
	if isnil(binding.world_runtime) {
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
	if wr.submit(task) {
		_ := <-task.done
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

fn (t PlayerBreakBlockTask) run(mut tx worldrt.WorldTx) {
	defer {
		t.done <- true
	}
	mut s := player_for_epoch(mut tx, t.session_runtime_id, t.epoch) or { return }
	complete_block_break(mut tx, mut s, types.BlockPosition{t.x, t.y, t.z}, t.old_id)
}

// complete_block_break destroys the block and runs everything that follows
// from it: the event, the drop, the container contents, the paired door half
// and the effects every player in the world sees.
//
// Both ways a block can be destroyed end up here. A client predicted destroy
// arrives as a PlayerBreakBlockTask, and a break the server itself finished
// calls in from tick_breaking, which is the only path that runs when the
// client has handed block breaking to the server.
fn complete_block_break(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition, old_id int) bool {
	air_id := world.air.network_id
	current_id := block_at(tx, pos.x, pos.y, pos.z)
	if current_id != old_id {
		s.resend_block(pos)
		return false
	}

	mut ctx := event.new_context(player.BlockBreakData{
		player:   s.player
		x:        pos.x
		y:        pos.y
		z:        pos.z
		block_id: old_id
	})
	s.player.handler.on_block_break(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return false
	}

	tx.set_block(pos.x, pos.y, pos.z, air_id)
	damage_held_item(mut s, 1)

	if s.player.game_mode() != .creative && s.can_harvest(old_id) {
		center := types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5}
		drop_name, drop_count := block_drop_for(tx.wr.services.game_data(), old_id)
		if drop_name != '' {
			spawn_dropped_item_stack(mut tx, drop_name, drop_count, center)
		}
		drop_block_experience(mut tx, old_id, center)
	}

	if b := block.get(old_id) {
		if b is block.ChestBlock {
			drop_chest_contents(mut tx, mut s, pos.x, pos.y, pos.z)
		}
		if b is block.JukeboxBlock {
			drop_jukebox_disc(mut tx, pos.x, pos.y, pos.z)
		}
	}

	if pair := door_pair_pos(tx, pos, old_id) {
		pair_id := block_at(tx, pair.x, pair.y, pair.z)
		if door_pair_matches(tx, old_id, pair_id) {
			tx.set_block(pair.x, pair.y, pair.z, air_id)
			tx.on_block_changed(pair.x, pair.y, pair.z)
			recompute_neighbor_blocks(mut tx, pair)
		}
	}

	broadcast_stop_cracking(mut tx, pos.x, pos.y, pos.z)
	broadcast_destroy_particles(mut tx, pos.x, pos.y, pos.z, old_id)
	broadcast_swing(mut tx, s)
	tx.on_block_changed(pos.x, pos.y, pos.z)
	recompute_neighbor_blocks(mut tx, pos)
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

fn (t PlayerPlaceBlockTask) run(mut tx worldrt.WorldTx) {
	mut placed := false
	defer {
		t.result <- placed
	}
	mut s := player_for_epoch(mut tx, t.session_runtime_id, t.epoch) or { return }
	pos := t.click_pos
	neighbor := face_offset(pos, t.click_face)
	clicked_id := block_at(tx, pos.x, pos.y, pos.z)

	if interact_block(mut tx, mut s, pos, clicked_id, t.click_face) {
		return
	}
	if use_item_on_block(mut tx, mut s, pos, clicked_id) {
		return
	}
	if t.runtime_id == 0 {
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	}

	mut target := pos
	if !is_replaceable(clicked_id) {
		target = neighbor
	}
	dim := tx.world().dimension
	if target.y < dim.min_y || target.y > dim.max_y() {
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	}
	if t.now_ms - t.last_place_ms < place_cooldown_ms {
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	}

	if merged := merged_slab(tx, clicked_id, t.runtime_id, t.click_face, t.clicked_y, true) {
		placed = replace_block_form(mut tx, mut s, pos, merged)
	} else if !can_place_block_on_face(tx, t.runtime_id, t.click_face, clicked_id) {
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	} else {
		placed_id := oriented_block(tx, t.runtime_id, t.click_face, t.clicked_y, t.yaw)
		target_id := block_at(tx, target.x, target.y, target.z)
		if merged2 := merged_slab(tx, target_id, t.runtime_id, t.click_face, t.clicked_y, false) {
			placed = replace_block_form(mut tx, mut s, target, merged2)
		} else if parts := door_placement(mut tx, placed_id, target, t.click_face, t.yaw) {
			placed = place_door_pair(mut tx, mut s, target, parts)
		} else {
			placed = place_block_form(mut tx, mut s, target, placed_id)
		}
	}

	if placed && !t.is_creative {
		consume_held_item(mut s)
	}
}

// Block picking is session local: it reads the current world and updates the
// inventory through Player's state lock.
fn (mut s NetworkSession) handle_block_pick_request(p proto.BlockPickRequestPacket) ! {
	s.apply_block_pick_request(p)
}

fn (mut s NetworkSession) apply_block_pick_request(p proto.BlockPickRequestPacket) {
	pos := proto.block_pos_from_legacy(p.position)
	runtime_id := s.block_at(pos.x, pos.y, pos.z)
	if runtime_id == world.air.network_id {
		return
	}
	item_id := s.hub.data.item_for_block(runtime_id)
	if item_id == 0 {
		return
	}

	if existing_slot := s.find_inventory_slot(item_id, runtime_id) {
		if existing_slot < player.hotbar_size {
			stack, net := s.inventory_stack_at(existing_slot)
			s.select_hotbar_slot(existing_slot, wrap_stack_id(stack, net))
		} else {
			s.swap_slot_into_hand(existing_slot)
		}
		return
	}
	if s.player.game_mode() != .creative {
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
	if empty_slot < player.hotbar_size {
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
	for slot in 0 .. player.inventory_slot_count {
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
	s.send_maybe_queued(&proto.PlayerHotbarPacket{
		selected_slot:      u32(slot)
		container_id:       .inventory
		should_select_slot: true
	}) or {}
	s.hub.broadcast_except(s.runtime_id, &proto.MobEquipmentPacket{
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		item:              proto.item_descriptor_v2(wrapped.item_stack)
		slot:              i8(slot)
		selected_slot:     i8(slot)
		container_id:      .inventory
	})
}
