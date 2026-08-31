module session

import crypto.md5
import bedrock_v.protocol.types
import server.internal.gamedata
import server.item
import bedrock_v.protocol.current as proto

const crafting_grid_small = [28, 29, 30, 31]
const crafting_grid_large = [32, 33, 34, 35, 36, 37, 38, 39, 40]

fn (s &NetworkSession) crafting_slot_net_id(slot int) int {
	mut m := s.crafting_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return s.crafting_slot_net_ids[slot] or { 0 }
}

fn (mut s NetworkSession) set_crafting_slot_net_id(slot int, net_id int) {
	s.crafting_mutex.lock()
	if net_id == 0 {
		s.crafting_slot_net_ids.delete(slot)
	} else {
		s.crafting_slot_net_ids[slot] = net_id
	}
	s.crafting_mutex.unlock()
}

fn (s &NetworkSession) workbench_open() bool {
	mut m := s.crafting_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return s.crafting_workbench_open
}

fn (mut s NetworkSession) set_workbench_open(open bool) {
	s.crafting_mutex.lock()
	s.crafting_workbench_open = open
	s.crafting_mutex.unlock()
}

fn (s &NetworkSession) crafting_grid_slots() []int {
	if s.workbench_open() {
		return crafting_grid_large
	}
	return crafting_grid_small
}

// attempt_craft resolves recipe_network_id against the grid; falls back to
// whatever the grid actually matches if the client's claimed id doesn't.
fn (mut tx WorldTx) attempt_craft(mut s NetworkSession, recipe_network_id u32, number_of_crafts i8) ?[]SlotChange {
	times := if number_of_crafts < 1 { 1 } else { int(number_of_crafts) }
	if requested := item.recipe_by_network_id(recipe_network_id) {
		if changes := tx.try_craft_recipe(mut s, requested, times) {
			return changes
		}
	} else {
		s.log.debug('attempt_craft: no registered recipe for network_id=${recipe_network_id}')
	}
	fallback := s.find_matching_recipe(times) or { return none }
	s.log.debug('attempt_craft: requested recipe network_id=${recipe_network_id} did not match the grid - falling back to recipe=${fallback.id} (network_id=${fallback.network_id}), which does')
	return tx.try_craft_recipe(mut s, fallback, times)
}

struct PlannedConsumption {
	slot  int
	units int
}

// plan_recipe_consumption checks whether recipe is satisfiable against the
// grid for times crafts without mutating anything. One occupied cell
// per required ingredient position, not an aggregated count from one slot.
fn (s &NetworkSession) plan_recipe_consumption(recipe item.Recipe, times int) ?[]PlannedConsumption {
	slots := s.crafting_grid_slots()
	mut claimed := map[int]bool{}
	mut plan := []PlannedConsumption{}
	for ingredient in recipe.ingredients {
		if ingredient.name == '' || ingredient.count <= 0 {
			continue
		}
		for _ in 0 .. ingredient.count {
			mut found := -1
			for slot in slots {
				if claimed[slot] {
					continue
				}
				net_id := s.crafting_slot_net_id(slot)
				if net_id == 0 {
					continue
				}
				stack := s.player.inv_stack(net_id) or { continue }
				if s.hub.data.item_name(stack.id) != ingredient.name || stack.count < times {
					continue
				}
				found = slot
				break
			}
			if found == -1 {
				return none
			}
			claimed[found] = true
			plan << PlannedConsumption{
				slot:  found
				units: times
			}
		}
	}
	return plan
}

// describe_crafting_grid renders the grid's contents for a debug log line,
// built only on the failure path.
fn (s &NetworkSession) describe_crafting_grid() string {
	mut seen := []string{}
	for slot in s.crafting_grid_slots() {
		net_id := s.crafting_slot_net_id(slot)
		if net_id == 0 {
			continue
		}
		stack := s.player.inv_stack(net_id) or { continue }
		seen << 'slot ${slot}: ${s.hub.data.item_name(stack.id)} x${stack.count} (id=${stack.id})'
	}
	return seen.join(', ')
}

fn (mut tx WorldTx) try_craft_recipe(mut s NetworkSession, recipe item.Recipe, times int) ?[]SlotChange {
	if recipe.block != 'crafting_table' {
		s.log.debug('try_craft_recipe: recipe ${recipe.id} (network_id=${recipe.network_id}) requires block=${recipe.block}, not crafting_table')
		return none
	}
	s.log.debug('try_craft_recipe: recipe=${recipe.id} network_id=${recipe.network_id} times=${times} workbench_open=${s.workbench_open()} grid_slots=${s.crafting_grid_slots()}')
	plan := s.plan_recipe_consumption(recipe, times) or {
		s.log.debug('try_craft_recipe: recipe=${recipe.id} could not be satisfied one cell per position - grid had [${s.describe_crafting_grid()}]')
		return none
	}
	mut changes := []SlotChange{}
	for p in plan {
		net_id := s.crafting_slot_net_id(p.slot)
		stack := s.player.inv_stack(net_id) or { continue }
		remaining := stack.count - p.units
		s.player.delete_stack(net_id)
		mut new_net := 0
		if remaining > 0 {
			mut leftover := stack
			leftover.count = remaining
			new_net = s.player.track_stack(leftover)
		}
		s.set_crafting_slot_net_id(p.slot, new_net)
		changes << slot_change(proto.FullContainerName{
			container: .crafting_input_container
		}, i8(p.slot), remaining, new_net)
	}
	output_id := s.hub.data.item_id(recipe.output_name)
	if output_id == 0 {
		s.log.debug('try_craft_recipe: recipe=${recipe.id} output ${recipe.output_name} has no numeric item id in gamedata')
		return none
	}
	count := s.clamp_stack_count(output_id, recipe.output_count * times)
	s.player.set_pending_creative(types.ItemStack{
		id:    output_id
		count: count
	})
	return changes
}

fn (s &NetworkSession) find_matching_recipe(times int) ?item.Recipe {
	for recipe in item.all_recipes() {
		if recipe.block != 'crafting_table' || recipe.ingredients.len == 0 {
			continue
		}
		if _ := s.plan_recipe_consumption(recipe, times) {
			return recipe
		}
	}
	return none
}

fn (s &NetworkSession) available_ingredient_count(name string) int {
	mut total := 0
	for slot in s.crafting_grid_slots() {
		net_id := s.crafting_slot_net_id(slot)
		if net_id == 0 {
			continue
		}
		if stack := s.player.inv_stack(net_id) {
			if s.hub.data.item_name(stack.id) == name {
				total += stack.count
			}
		}
	}
	for slot in 0 .. inventory_slot_count {
		net_id := s.player.inv_slot(slot) or { continue }
		if stack := s.player.inv_stack(net_id) {
			if s.hub.data.item_name(stack.id) == name {
				total += stack.count
			}
		}
	}
	return total
}

// consume_ingredient removes need units of name, grid first then
// inventory. Callers must already have verified availability.
fn (mut s NetworkSession) consume_ingredient(name string, need int, mut changes []SlotChange) {
	mut remaining := need
	for slot in s.crafting_grid_slots() {
		if remaining <= 0 {
			break
		}
		net_id := s.crafting_slot_net_id(slot)
		if net_id == 0 {
			continue
		}
		stack := s.player.inv_stack(net_id) or { continue }
		if s.hub.data.item_name(stack.id) != name {
			continue
		}
		take := if stack.count < remaining { stack.count } else { remaining }
		remaining -= take
		left := stack.count - take
		s.player.delete_stack(net_id)
		mut new_net := 0
		if left > 0 {
			mut leftover := stack
			leftover.count = left
			new_net = s.player.track_stack(leftover)
		}
		s.set_crafting_slot_net_id(slot, new_net)
		changes << slot_change(proto.FullContainerName{
			container: .crafting_input_container
		}, i8(slot), left, new_net)
	}
	for slot in 0 .. inventory_slot_count {
		if remaining <= 0 {
			break
		}
		net_id := s.player.inv_slot(slot) or { continue }
		stack := s.player.inv_stack(net_id) or { continue }
		if s.hub.data.item_name(stack.id) != name {
			continue
		}
		take := if stack.count < remaining { stack.count } else { remaining }
		remaining -= take
		left := stack.count - take
		s.player.delete_stack(net_id)
		mut new_net := 0
		if left > 0 {
			mut leftover := stack
			leftover.count = left
			new_net = s.player.track_stack(leftover)
			s.player.set_slot(slot, new_net)
		} else {
			s.player.delete_slot(slot)
		}
		changes << slot_change(proto.FullContainerName{
			container: .combined_hotbar_and_inventory_container
		}, i8(slot), left, new_net)
	}
}

fn (mut tx WorldTx) attempt_auto_craft(mut s NetworkSession, recipe_network_id u32, number_of_crafts i8) ?[]SlotChange {
	recipe := item.recipe_by_network_id(recipe_network_id) or { return none }
	if recipe.block != 'crafting_table' {
		return none
	}
	times := if number_of_crafts < 1 { 1 } else { int(number_of_crafts) }
	for ingredient in recipe.ingredients {
		if ingredient.name == '' || ingredient.count <= 0 {
			continue
		}
		if s.available_ingredient_count(ingredient.name) < ingredient.count * times {
			return none
		}
	}
	mut changes := []SlotChange{}
	for ingredient in recipe.ingredients {
		if ingredient.name == '' || ingredient.count <= 0 {
			continue
		}
		s.consume_ingredient(ingredient.name, ingredient.count * times, mut changes)
	}
	output_id := s.hub.data.item_id(recipe.output_name)
	if output_id == 0 {
		return none
	}
	count := s.clamp_stack_count(output_id, recipe.output_count * times)
	s.player.set_pending_creative(types.ItemStack{
		id:    output_id
		count: count
	})
	return changes
}

fn (mut tx WorldTx) open_workbench(mut s NetworkSession, pos types.BlockPosition) {
	s.log.debug('open_workbench: opening at ${pos}')
	s.close_chest_container(mut tx)
	s.set_workbench_open(true)
	s.deliver(&proto.ContainerOpenPacket{
		container_id:    proto.ContainerID.first
		container_type:  proto.ContainerType.workbench
		position:        proto.block_pos(pos)
		target_actor_id: proto.actor_unique_id(-1)
	})
}

// return_or_drop_stack gives stack back to an inventory slot if one's
// free, otherwise drops it at the player's feet. Never silently discards.
fn (mut s NetworkSession) return_or_drop_stack(stack types.ItemStack) {
	if dest := s.first_empty_slot() {
		returned_net := s.player.track_stack(stack)
		s.player.set_slot(dest, returned_net)
		s.send_slot_update(dest, types.ItemStackWrapper{
			item_stack: stack
			stack_id:   returned_net
		})
		return
	}
	mut wr := s.current_world_runtime()
	if !isnil(wr) {
		center := s.player.position()
		spawn_dropped_item_stack(mut wr, s.hub.data.item_name(stack.id), stack.count, center)
	}
}

// release_crafting_grid_slots returns whatever the given slots hold and
// clears their tracking. Safe on an already empty grid.
fn (mut s NetworkSession) release_crafting_grid_slots(slots []int) {
	for slot in slots {
		net_id := s.crafting_slot_net_id(slot)
		if net_id == 0 {
			continue
		}
		stack := s.player.inv_stack(net_id) or {
			s.set_crafting_slot_net_id(slot, 0)
			continue
		}
		s.player.delete_stack(net_id)
		s.set_crafting_slot_net_id(slot, 0)
		s.return_or_drop_stack(stack)
	}
}

fn (mut s NetworkSession) release_cursor() {
	net_id := s.cursor_slot_net_id()
	if net_id == 0 {
		return
	}
	stack := s.player.inv_stack(net_id) or {
		s.set_cursor_slot_net_id(0)
		return
	}
	s.player.delete_stack(net_id)
	s.set_cursor_slot_net_id(0)
	s.return_or_drop_stack(stack)
}

// release_crafting_state returns everything the grid and cursor hold, the
// full cleanup a disconnect needs, since the client isn't guaranteed to
// send a clean ContainerClose first.
fn (mut s NetworkSession) release_crafting_state() {
	s.release_crafting_grid_slots(crafting_grid_small)
	s.release_crafting_grid_slots(crafting_grid_large)
	s.release_cursor()
}

fn (mut s NetworkSession) close_workbench() {
	if !s.workbench_open() {
		return
	}
	s.release_crafting_grid_slots(crafting_grid_large)
	s.set_workbench_open(false)
}

struct CloseWorkbenchTask {
	runtime_id u64
	epoch      i64
}

fn (t CloseWorkbenchTask) name() string {
	return 'CloseWorkbenchTask'
}

fn (t CloseWorkbenchTask) run(mut tx WorldTx) {
	mut target := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	target.close_workbench()
}

fn (mut s NetworkSession) release_workbench() {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	wr.submit(CloseWorkbenchTask{
		runtime_id: rid
		epoch:      epoch
	})
}

fn recipe_uuid(id string) proto.Uuid {
	sum := md5.sum(id.bytes())
	mut bytes := [16]u8{}
	for i in 0 .. 16 {
		bytes[i] = sum[i]
	}
	return proto.Uuid{
		bytes: bytes
	}
}

const always_unlocked = proto.RecipeUnlockingRequirement{
	context: proto.UnlockingContext.always_unlocked
}

fn crafting_data_packet(data gamedata.GameData) &proto.CraftingDataPacket {
	mut shaped_recipes := []proto.ShapedRecipe{}
	mut shapeless_recipes := []proto.ShapelessRecipe{}
	for r in item.all_recipes() {
		output_id := data.item_id(r.output_name)
		production_list := [
			proto.NetworkItemInstanceDescriptor{
				id:         output_id
				stack_size: u16(r.output_count)
			},
		]
		if r.width > 0 && r.height > 0 {
			mut cells := []proto.CraftingRecipeIngredient{cap: r.pattern.len}
			for cell in r.pattern {
				if cell == '' {
					cells << proto.CraftingRecipeIngredient{
						descriptor: proto.CraftingDescEmpty{}
					}
					continue
				}
				cells << proto.CraftingRecipeIngredient{
					descriptor: proto.CraftingDescName{
						item_id: cell
					}
					stack_size: 1
				}
			}
			shaped_recipes << proto.ShapedRecipe{
				recipe_unique_id:      r.id
				width:                 r.width
				height:                r.height
				ingredients:           cells
				production_list:       production_list
				recipe_id:             recipe_uuid(r.id)
				recipe_tag:            r.block
				priority:              0
				assume_symmetry:       true
				unlocking_requirement: always_unlocked
				network_id:            i32(r.network_id)
			}
			continue
		}
		mut ingredients := []proto.CraftingRecipeIngredient{cap: r.ingredients.len}
		for ingredient in r.ingredients {
			ingredients << proto.CraftingRecipeIngredient{
				descriptor: proto.CraftingDescName{
					item_id: ingredient.name
				}
				stack_size: ingredient.count
			}
		}
		shapeless_recipes << proto.ShapelessRecipe{
			recipe_unique_id:      r.id
			ingredient_list:       ingredients
			production_list:       production_list
			recipe_id:             recipe_uuid(r.id)
			recipe_tag:            r.block
			priority:              0
			unlocking_requirement: always_unlocked
			network_id:            i32(r.network_id)
		}
	}
	return &proto.CraftingDataPacket{
		shaped_recipes:    shaped_recipes
		shapeless_recipes: shapeless_recipes
		clear_recipes:     true
	}
}
