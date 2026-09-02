module session

import math
import rand
import bedrock_v.protocol.types
import server.block
import server.entity
import server.item
import bedrock_v.protocol.current as proto
import server.internal.gamedata
import server.worldrt
import server.player

fn spawn_dropped_item_entity(mut tx worldrt.WorldTx, stack types.ItemStack, max_stack_size int, pos types.Vector3, velocity types.Vector3, pickup_delay_ticks i64) {
	if stack.count <= 0 || stack.id == 0 {
		return
	}
	behaviour := entity.new_item_behaviour(stack, max_stack_size, pickup_delay_ticks)
	mut e := tx.wr.entities.spawn(behaviour, pos)
	e.set_velocity(velocity)
}

fn spawn_dropped_item_stack(mut tx worldrt.WorldTx, item_name string, count int, pos types.Vector3) {
	if count <= 0 {
		return
	}
	id := tx.wr.services.game_data().item_id(item_name)
	if id == 0 {
		return
	}
	max_stack := item.max_stack_size(item_name)
	stack := types.ItemStack{
		id:    id
		count: count
	}
	velocity := types.Vector3{
		x: (rand.f32() * 0.2) - 0.1
		y: 0.2
		z: (rand.f32() * 0.2) - 0.1
	}
	spawn_dropped_item_entity(mut tx, stack, max_stack, pos, velocity, entity.item_pickup_delay_ticks)
}

fn drop_player_item(mut tx worldrt.WorldTx, s &NetworkSession, stack types.ItemStack) {
	feet := s.feet_position()
	movement := s.player.movement()
	yaw_rad := f32(movement.yaw) * f32(math.pi) / 180.0
	pitch_rad := f32(movement.pitch) * f32(math.pi) / 180.0
	dir_x := -math.sinf(yaw_rad) * math.cosf(pitch_rad)
	dir_y := -math.sinf(pitch_rad)
	dir_z := math.cosf(yaw_rad) * math.cosf(pitch_rad)
	drop_pos := types.Vector3{feet.x, feet.y + 1.3, feet.z}
	velocity := types.Vector3{dir_x * 0.4, dir_y * 0.4 + 0.1, dir_z * 0.4}
	max_stack := s.max_stack_size_for_numeric(stack.id)
	spawn_dropped_item_entity(mut tx, stack, max_stack, drop_pos, velocity, entity.item_drop_pickup_delay_ticks)
}

// block_drop_for answers what a broken block leaves behind. It reads the
// block registry and the item table, both of which are process wide and
// immutable. It takes the game data rather than a world.
fn block_drop_for(data &gamedata.GameData, block_id int) (string, int) {
	identifier := if b := block.get(block_id) { b.identifier() } else { '' }
	if identifier != '' {
		if loot := block.loot_for_block(identifier) {
			return loot.item_name, entity.rand_int_range(loot.min_count, loot.max_count)
		}
	}
	item_id := data.item_for_block(block_id)
	if item_id == 0 {
		return '', 0
	}
	return data.item_name(item_id), 1
}

fn (mut s NetworkSession) try_collect_item(stack types.ItemStack) int {
	if s.player.is_dead() {
		return 0
	}
	max := s.max_stack_size_for_numeric(stack.id)
	mut remaining := stack.count
	for slot in 0 .. player.inventory_slot_count {
		if remaining <= 0 {
			break
		}
		existing, net := s.inventory_stack_at(slot)
		if net == 0 || !stack_merge_compatible(existing, stack) {
			continue
		}
		room := max - existing.count
		if room <= 0 {
			continue
		}
		add := if remaining < room { remaining } else { room }
		mut updated := existing
		updated.count += add
		s.player.put_stack(net, updated)
		remaining -= add
		s.send_slot_update(slot, wrap_stack_id(updated, net))
	}
	for remaining > 0 {
		slot := s.first_empty_slot() or { break }
		add := if remaining < max { remaining } else { max }
		mut new_stack := stack
		new_stack.count = add
		net := s.player.track_stack(new_stack)
		s.player.set_slot(slot, net)
		remaining -= add
		s.send_slot_update(slot, wrap_stack_id(new_stack, net))
	}
	return stack.count - remaining
}

fn (mut h WorldEntityHost) spawn_dropped_item(item_name string, count int, pos types.Vector3) {
	mut tx := h.tx()
	spawn_dropped_item_stack(mut tx, item_name, count, pos)
}

fn (mut h WorldEntityHost) collect_item(runtime_id u64, stack types.ItemStack) int {
	mut a := h.wr.entities.actor_by_runtime_id(runtime_id) or { return 0 }
	if mut a is NetworkSession {
		return a.try_collect_item(stack)
	}
	return 0
}

// notify_item_taken broadcasts the pickup animation to this world's
// viewers.
fn (mut h WorldEntityHost) notify_item_taken(item_runtime_id u64, taker_runtime_id u64) {
	h.wr.broadcast_world(&proto.TakeItemActorPacket{
		item_runtime_id:  proto.actor_runtime_id(item_runtime_id)
		actor_runtime_id: proto.actor_runtime_id(taker_runtime_id)
	})
}
