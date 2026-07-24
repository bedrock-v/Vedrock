module session

import math
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

// break_grace_ticks absorbs latency jitter around the expected break time
// boundary so a legitimate client isn't rejected for arriving a tick or two
// early.
const break_grace_ticks = i64(2)

// required_break_ticks approximates vanilla's break time formula
// (hardness * 30 / mining_speed). This is deliberately not vanilla exact.
fn required_break_ticks(hardness f32, mining_speed f32) i64 {
	if hardness <= 0 {
		return 0
	}
	return i64(math.ceil(hardness * 30.0 / mining_speed))
}

fn (s &NetworkSession) held_mining_speed() f32 {
	_, name := s.held_stack_and_name()
	if it := s.hub.items.get(name) {
		return it.mining_speed()
	}
	return 1.0
}

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
	return s.player.game_mode() != protocol.game_type_spectator
		&& s.player.game_mode() != protocol.game_type_survival_spectator
		&& s.player.game_mode() != protocol.game_type_creative_spectator
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
		} else if ue.action_type == protocol.item_use_on_entity_action_interact {
			s.handle_entity_interact(ue.target_entity_runtime_id)
		}
		return
	}
	if p.transaction_type != protocol.inventory_transaction_type_use_item {
		return
	}
	ut := p.use_item
	match ut.action_type {
		protocol.item_use_action_click_block {
			if s.player.is_dead() || !s.can_interact() {
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
			runtime_id := s.placement_runtime_id(ut.held_item.item_stack)
			binding := s.world_binding()
			if isnil(binding.world_runtime) {
				return
			}
			mut wr := binding.world_runtime
			now := time.now().unix_milli()
			task := PlayerPlaceBlockTask{
				session_runtime_id: s.runtime_id
				epoch:              binding.epoch
				click_pos:          ut.block_position
				click_face:         int(ut.block_face)
				clicked_y:          ut.clicked_position.y
				runtime_id:         runtime_id
				yaw:                s.player.movement().yaw
				now_ms:             now
				last_place_ms:      s.last_place_ms
				is_creative:        s.player.game_mode() == protocol.game_type_creative
			}
			if wr.submit(task) {
				placed := <-task.result
				if placed {
					s.last_place_ms = now
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

fn (s &NetworkSession) placement_runtime_id(packet_stack types.ItemStack) int {
	stack := if s.player.game_mode() == protocol.game_type_creative {
		packet_stack
	} else {
		held, _ := s.inventory_stack_at(s.player.held_slot())
		held
	}
	if stack.count <= 0 || stack.id == 0 {
		return 0
	}
	if stack.block_runtime_id != 0 {
		return stack.block_runtime_id
	}
	held_name := s.hub.data.item_name(stack.id)
	if held_item := s.hub.items.get(held_name) {
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
	if s.player.game_mode() == protocol.game_type_creative
		|| s.player.game_mode() == protocol.game_type_creative_spectator {
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
			s.request_respawn()
		}
		else {}
	}
}

fn (mut s NetworkSession) handle_start_break(pos types.BlockPosition, click_face int) {
	if s.player.is_dead() || !s.can_interact() {
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	if old_id == world.air.network_id || !s.within_place_reach(pos) {
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
	s.breaking = BreakProgress{pos.x, pos.y, pos.z, old_id, s.hub.current_tick()}
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

// broadcast_swing sends this session's arm swing animation globally. Only
// handle_start_break still uses this global form. Every block-mutating
// swing broadcast goes through WorldTx.broadcast_swing instead, scoped to
// the world.
fn (mut s NetworkSession) broadcast_swing() {
	s.hub.broadcast_except(s.runtime_id, &protocol.AnimatePacket{
		action:           protocol.animate_action_swing_arm
		actor_runtime_id: s.runtime_id
	})
}

// place_reach_sq returns the squared placement reach for the player's
// current gamemode.
fn (s &NetworkSession) place_reach_sq() f32 {
	if s.player.game_mode() == protocol.game_type_creative
		|| s.player.game_mode() == protocol.game_type_creative_spectator {
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
	s.deliver(&protocol.UpdateBlockPacket{
		block_position:   pos
		block_runtime_id: s.block_at(pos.x, pos.y, pos.z)
		flags:            block_update_flags
		data_layer_id:    0
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
		return
	}
	old_id := s.block_at(pos.x, pos.y, pos.z)
	air_id := world.air.network_id
	if old_id == air_id {
		return
	}
	if !s.within_place_reach(pos) {
		s.resend_block(pos)
		return
	}
	if s.player.game_mode() != protocol.game_type_creative && !s.hub.blocks.breakable(old_id) {
		s.send_maybe_queued(&protocol.UpdateBlockPacket{
			block_position:   pos
			block_runtime_id: old_id
			flags:            block_update_flags
			data_layer_id:    0
		})!
		return
	}
	if s.player.game_mode() != protocol.game_type_creative {
		required := required_break_ticks(s.hub.blocks.hardness(old_id), s.held_mining_speed())
		matches := if bp := s.breaking {
			bp.x == pos.x && bp.y == pos.y && bp.z == pos.z && bp.block_id == old_id
		} else {
			false
		}
		elapsed := if bp := s.breaking { s.hub.current_tick() - bp.started_tick } else { 0 }
		if !matches || elapsed < required - break_grace_ticks {
			s.resend_block(pos)
			return
		}
	}
	s.breaking = none
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

fn (t PlayerBreakBlockTask) run(mut tx WorldTx) {
	defer {
		t.done <- true
	}
	mut s := tx.player_for_epoch(t.session_runtime_id, t.epoch) or { return }
	pos := types.BlockPosition{t.x, t.y, t.z}
	air_id := world.air.network_id

	current_id := tx.block_at(t.x, t.y, t.z)
	if current_id != t.old_id {
		s.resend_block(pos)
		return
	}

	mut ctx := event.new_context(event.BlockBreakData{
		player:   s
		x:        t.x
		y:        t.y
		z:        t.z
		block_id: t.old_id
	})
	tx.wr.events.block_break(mut ctx)
	if ctx.is_cancelled() {
		s.resend_block(pos)
		return
	}

	tx.set_block(t.x, t.y, t.z, air_id)
	tx.damage_held_item(mut s, 1)

	if pair := tx.door_pair_pos(pos, t.old_id) {
		pair_id := tx.block_at(pair.x, pair.y, pair.z)
		if tx.door_pair_matches(t.old_id, pair_id) {
			tx.set_block(pair.x, pair.y, pair.z, air_id)
			tx.on_block_changed(pair.x, pair.y, pair.z)
			tx.recompute_neighbor_blocks(pair)
		}
	}

	tx.broadcast_destroy_particles(t.x, t.y, t.z, t.old_id)
	tx.broadcast_swing(s)
	tx.on_block_changed(t.x, t.y, t.z)
	tx.recompute_neighbor_blocks(pos)
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

fn (t PlayerPlaceBlockTask) run(mut tx WorldTx) {
	mut placed := false
	defer {
		t.result <- placed
	}
	mut s := tx.player_for_epoch(t.session_runtime_id, t.epoch) or { return }
	pos := t.click_pos
	neighbor := face_offset(pos, t.click_face)
	clicked_id := tx.block_at(pos.x, pos.y, pos.z)

	if tx.interact_block(mut s, pos, clicked_id, t.click_face) {
		return
	}
	if tx.use_item_on_block(mut s, pos, clicked_id) {
		return
	}
	if t.runtime_id == 0 {
		return
	}

	mut target := pos
	if !tx.is_replaceable(clicked_id) {
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

	if merged := tx.merged_slab(clicked_id, t.runtime_id, t.click_face, t.clicked_y, true) {
		placed = tx.replace_block_form(mut s, pos, merged)
	} else if !tx.can_place_block_on_face(t.runtime_id, t.click_face, clicked_id) {
		s.resend_block(pos)
		s.resend_block(neighbor)
		return
	} else {
		placed_id := tx.oriented_block(t.runtime_id, t.click_face, t.clicked_y, t.yaw)
		target_id := tx.block_at(target.x, target.y, target.z)
		if merged2 := tx.merged_slab(target_id, t.runtime_id, t.click_face, t.clicked_y, false) {
			placed = tx.replace_block_form(mut s, target, merged2)
		} else if parts := tx.door_placement(placed_id, target, t.click_face, t.yaw) {
			placed = tx.place_door_pair(mut s, target, parts)
		} else {
			placed = tx.place_block_form(mut s, target, placed_id)
		}
	}

	if placed && !t.is_creative {
		tx.consume_held_item(mut s)
	}
}

// Block picking is session local: it reads the current world and updates the
// inventory through Player's state lock.
fn (mut s NetworkSession) handle_block_pick_request(p protocol.BlockPickRequestPacket) ! {
	s.apply_block_pick_request(p)
}

fn (mut s NetworkSession) apply_block_pick_request(p protocol.BlockPickRequestPacket) {
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
	if s.player.game_mode() != protocol.game_type_creative {
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
	s.send_maybe_queued(&protocol.PlayerHotbarPacket{
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
