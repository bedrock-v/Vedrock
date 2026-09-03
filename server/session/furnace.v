module session

import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import bedrock_v.protocol.version.v662.packets as versioned
import server.block
import server.item
import server.world.db
import server.worldrt

// Furnace progress ids, as the client's own container data. flame is drawn
// from burn_progress against burn_total, and the arrow from cook_progress
// against cook_total.
const furnace_data_cook_progress = i32(0)
const furnace_data_burn_progress = i32(1)
const furnace_data_burn_total = i32(2)

// SessionFurnaceTicker advances every burning furnace in a world once per
// simulated step. It holds no state: the progress lives on the world, and the
// contents in the same container storage every other container uses.
struct SessionFurnaceTicker {}

fn (mut t SessionFurnaceTicker) tick_block_entities(mut tx worldrt.WorldTx) {
	for pos in tx.wr.world.burning_furnaces() {
		tick_furnace(mut tx, pos.x, pos.y, pos.z)
	}
}

// furnace_at resolves the furnace block at a position, lit or not.
fn furnace_at(tx &worldrt.WorldTx, x int, y int, z int) ?(int, block.FurnaceVariant) {
	block_id := block_at(tx, x, y, z)
	b := block.get(block_id) or { return none }
	variant := block.furnace_variant(b.identifier()) or { return none }
	return block_id, variant
}

// tick_furnace advances one furnace: burn down the fuel, light more when there
// is something to cook, move the cook along and hand over the result.
fn tick_furnace(mut tx worldrt.WorldTx, x int, y int, z int) {
	block_id, variant := furnace_at(tx, x, y, z) or {
		// The block is gone; drop whatever progress it had with it.
		tx.wr.world.clear_furnace_state(x, y, z)
		return
	}
	before := tx.wr.world.furnace_state(x, y, z)
	mut state := db.FurnaceState{
		burn_ticks: if before.burn_ticks > 0 { before.burn_ticks - 1 } else { 0 }
		burn_total: before.burn_total
		cook_ticks: before.cook_ticks
	}
	smeltable := furnace_can_cook(mut tx, x, y, z)
	if state.burn_ticks <= 0 && smeltable {
		state = light_furnace(mut tx, x, y, z, state)
	}
	if state.burn_ticks > 0 && smeltable {
		state = db.FurnaceState{
			burn_ticks: state.burn_ticks
			burn_total: state.burn_total
			cook_ticks: state.cook_ticks + 1
		}
		if state.cook_ticks >= variant.cook_ticks() {
			finish_cooking(mut tx, x, y, z)
			state = db.FurnaceState{
				burn_ticks: state.burn_ticks
				burn_total: state.burn_total
			}
		}
	} else {
		state = db.FurnaceState{
			burn_ticks: state.burn_ticks
			burn_total: state.burn_total
		}
	}
	if state.is_idle() && !smeltable {
		tx.wr.world.clear_furnace_state(x, y, z)
	} else {
		tx.wr.world.set_furnace_state(x, y, z, state)
	}
	sync_furnace_block(mut tx, x, y, z, block_id, state.burn_ticks > 0)
	broadcast_furnace_progress(mut tx, x, y, z, state)
}

// furnace_slot reads one of a furnace's three slots.
fn furnace_slot(mut tx worldrt.WorldTx, x int, y int, z int, slot int) types.ItemStack {
	slots := tx.wr.world.container_slots(x, y, z)
	if slot < 0 || slot >= slots.len {
		return types.ItemStack{}
	}
	return slots[slot]
}

// furnace_can_cook reports whether the input smelts into something the output
// slot still has room for.
fn furnace_can_cook(mut tx worldrt.WorldTx, x int, y int, z int) bool {
	input := furnace_slot(mut tx, x, y, z, block.furnace_slot_input)
	if input.count <= 0 || input.id == 0 {
		return false
	}
	recipe := item.smelting_recipe(tx.wr.services.game_data().item_name(input.id)) or {
		return false
	}
	result_id := tx.wr.services.game_data().item_id(recipe.output)
	if result_id == 0 {
		return false
	}
	output := furnace_slot(mut tx, x, y, z, block.furnace_slot_output)
	if output.count <= 0 || output.id == 0 {
		return true
	}
	if output.id != result_id {
		return false
	}
	return output.count < item.max_stack_size(recipe.output)
}

// light_furnace consumes one piece of fuel, if there is any.
fn light_furnace(mut tx worldrt.WorldTx, x int, y int, z int, state db.FurnaceState) db.FurnaceState {
	fuel := furnace_slot(mut tx, x, y, z, block.furnace_slot_fuel)
	if fuel.count <= 0 || fuel.id == 0 {
		return state
	}
	burn := item.fuel_burn_ticks(tx.wr.services.game_data().item_name(fuel.id)) or { return state }
	mut remaining := fuel
	remaining.count--
	tx.wr.world.set_container_slot(x, y, z, block.furnace_slot_fuel, remaining)
	return db.FurnaceState{
		burn_ticks: burn
		burn_total: burn
		cook_ticks: state.cook_ticks
	}
}

// finish_cooking takes one input and puts the result in the output slot.
fn finish_cooking(mut tx worldrt.WorldTx, x int, y int, z int) {
	input := furnace_slot(mut tx, x, y, z, block.furnace_slot_input)
	if input.count <= 0 || input.id == 0 {
		return
	}
	recipe := item.smelting_recipe(tx.wr.services.game_data().item_name(input.id)) or { return }
	result_id := tx.wr.services.game_data().item_id(recipe.output)
	if result_id == 0 {
		return
	}
	mut remaining := input
	remaining.count--
	tx.wr.world.set_container_slot(x, y, z, block.furnace_slot_input, remaining)

	mut output := furnace_slot(mut tx, x, y, z, block.furnace_slot_output)
	if output.count <= 0 || output.id == 0 {
		output = types.ItemStack{
			id:    result_id
			count: 1
		}
	} else {
		output.count++
	}
	tx.wr.world.set_container_slot(x, y, z, block.furnace_slot_output, output)
}

// sync_furnace_block swaps the block between its lit and unlit forms so the
// furnace looks like what it is doing.
fn sync_furnace_block(mut tx worldrt.WorldTx, x int, y int, z int, block_id int, burning bool) {
	if burning {
		if lit := block.lit_furnace_id(block_id) {
			tx.set_block(x, y, z, lit)
		}
		return
	}
	if unlit := block.unlit_furnace_id(block_id) {
		tx.set_block(x, y, z, unlit)
	}
}

// broadcast_furnace_progress sends the flame and arrow to whoever has the
// furnace open. The packet has no alias in the protocol's current set, so it
// is reached through the version it was last changed in.
fn broadcast_furnace_progress(mut tx worldrt.WorldTx, x int, y int, z int, state db.FurnaceState) {
	pos := types.BlockPosition{x, y, z}
	for mut actor in tx.wr.entities.player_actors() {
		mut s := as_network_session(mut actor) or { continue }
		held := s.open_container_position() or { continue }
		if held != pos {
			continue
		}
		s.deliver(furnace_data_packet(furnace_data_cook_progress, i32(state.cook_ticks)))
		s.deliver(furnace_data_packet(furnace_data_burn_progress, i32(state.burn_ticks)))
		s.deliver(furnace_data_packet(furnace_data_burn_total, i32(state.burn_total)))
	}
}

fn furnace_data_packet(id i32, value i32) &versioned.ContainerSetDataPacket {
	return &versioned.ContainerSetDataPacket{
		container_id: proto.ContainerID.first
		id:           id
		value:        value
	}
}

// wake_furnace starts the tick visiting a furnace, which is what makes one
// begin after something is put into it.
fn wake_furnace(mut tx worldrt.WorldTx, x int, y int, z int) {
	if tx.wr.world.tracks_furnace(x, y, z) {
		return
	}
	if !furnace_can_cook(mut tx, x, y, z) {
		return
	}
	tx.wr.world.set_furnace_state(x, y, z, db.FurnaceState{})
}

// open_furnace shows a furnace's three slots on the client's furnace screen.
// The contents live in the same per-position container storage every other
// container uses; only the screen and the slot count differ.
fn open_furnace(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition, variant block.FurnaceVariant) {
	s.close_chest_container(mut tx)
	if !tx.wr.world.try_hold_container(pos.x, pos.y, pos.z, s.runtime_id) {
		return
	}
	s.set_open_container_position(pos)
	stacks := tx.wr.world.container_slots(pos.x, pos.y, pos.z)
	mut descriptors := []proto.NetworkItemStackDescriptorV2{cap: block.furnace_slot_count}
	mut slot_net_ids := map[int]int{}
	for slot in 0 .. block.furnace_slot_count {
		stack := stacks[slot] or { types.ItemStack{} }
		if stack.count > 0 && stack.id != 0 {
			net_id := s.player.track_stack(stack)
			slot_net_ids[slot] = net_id
			descriptors << proto.item_descriptor_v2_tracked(stack, net_id)
		} else {
			descriptors << proto.item_descriptor_v2(stack)
		}
	}
	s.set_open_container_slots(slot_net_ids)
	s.deliver(&proto.ContainerOpenPacket{
		container_id:    proto.ContainerID.first
		container_type:  furnace_screen(variant)
		position:        proto.block_pos(pos)
		target_actor_id: proto.actor_unique_id(-1)
	})
	s.deliver(&proto.InventoryContentPacket{
		inventory_id:        u32(chest_dynamic_container_id())
		slots:               descriptors
		container_name_data: proto.FullContainerName{
			container:  proto.ContainerEnumName.dynamic_container
			dynamic_id: i32(chest_dynamic_container_id())
		}
		storage_item:        proto.item_descriptor_v2(types.ItemStack{})
	})
	state := tx.wr.world.furnace_state(pos.x, pos.y, pos.z)
	s.deliver(furnace_data_packet(furnace_data_cook_progress, i32(state.cook_ticks)))
	s.deliver(furnace_data_packet(furnace_data_burn_progress, i32(state.burn_ticks)))
	s.deliver(furnace_data_packet(furnace_data_burn_total, i32(state.burn_total)))
}

fn furnace_screen(variant block.FurnaceVariant) proto.ContainerType {
	return match variant {
		.furnace { proto.ContainerType.furnace }
		.blast_furnace { proto.ContainerType.blast_furnace }
		.smoker { proto.ContainerType.smoker }
	}
}
