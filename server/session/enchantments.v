module session

import rand
import bedrock_v.protocol.types
import server.enchant
import server.internal.gamedata
import server.item
import server.player
import server.worldrt

// fire_aspect_ticks_per_level is how long a hit sets its victim burning for
// each level of Fire Aspect.
const fire_aspect_ticks_per_level = i64(4 * 20)

// knockback_per_level is the extra horizontal push each level of Knockback
// adds to a hit.
const knockback_per_level = f32(0.5)

// held_enchantments is what the player's held item carries.
fn (s &NetworkSession) held_enchantments() []enchant.Applied {
	stack, _ := s.held_stack_and_name()
	return item.enchantments_from_nbt(stack.raw_extra_data)
}

// held_enchantment_level is the level of one enchantment on the held item, 0
// when it is not there.
fn (s &NetworkSession) held_enchantment_level(name string) int {
	stack, _ := s.held_stack_and_name()
	return item.enchantment_level(stack.raw_extra_data, name)
}

// enchanted_attack_damage is what the held weapon hits for once its
// enchantments are counted.
fn (s &NetworkSession) enchanted_attack_damage(base f32) f32 {
	return base + enchant.attack_bonus(s.held_enchantments())
}

// enchanted_knockback is the horizontal push a hit lands with.
fn (s &NetworkSession) enchanted_knockback(base f32) f32 {
	return base + knockback_per_level * f32(s.held_enchantment_level('knockback'))
}

// fire_aspect_ticks is how long the held weapon sets a victim burning for.
fn (s &NetworkSession) fire_aspect_ticks() i64 {
	return fire_aspect_ticks_per_level * i64(s.held_enchantment_level('fire_aspect'))
}

// efficiency_bonus is the mining speed Efficiency adds, which is level squared
// plus one on top of whatever the tool was already worth.
fn efficiency_bonus(level int) f32 {
	if level <= 0 {
		return 0
	}
	return f32(level * level + 1)
}

// survives_unbreaking rolls whether a point of durability damage is skipped.
// Each level of Unbreaking makes an item last proportionally longer.
fn survives_unbreaking(level int) bool {
	if level <= 0 {
		return false
	}
	return rand.intn(level + 1) or { 0 } != 0
}

// silk_touch_drop is the block itself rather than what breaking it normally
// leaves, when the held tool has Silk Touch and the block has a form to drop.
fn (s &NetworkSession) silk_touch_drop(block_id int) ?string {
	if s.held_enchantment_level('silk_touch') <= 0 {
		return none
	}
	item_id := s.hub.data.item_for_block(block_id)
	if item_id == 0 {
		return none
	}
	return s.hub.data.item_name(item_id)
}

// fortune_count multiplies a drop the way Fortune does: usually nothing, and
// at best one extra drop per level. Drops that are the block itself - stone,
// ores that drop their own block - are not multiplied.
fn fortune_count(base int, level int) int {
	if level <= 0 || base <= 0 {
		return base
	}
	bonus := rand.intn(level + 1) or { 0 }
	return base + bonus
}

// ignite_victim sets a victim burning for as long as the attacker's Fire
// Aspect says.
fn ignite_victim(mut victim NetworkSession, ticks i64) {
	if ticks <= 0 || victim.player.fire_ticks() >= ticks {
		return
	}
	victim.player.set_fire_ticks(ticks)
}

// block_center is where a block's drops appear.
fn block_center(pos types.BlockPosition) types.Vector3 {
	return types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5}
}

// harvested_drop is what breaking a block leaves for this player: the block
// itself when the held tool has Silk Touch, and otherwise the block's normal
// drop, multiplied by Fortune where that applies.
fn (s &NetworkSession) harvested_drop(data &gamedata.GameData, block_id int) (string, int) {
	if silk := s.silk_touch_drop(block_id) {
		return silk, 1
	}
	drop_name, drop_count := block_drop_for(data, block_id)
	if drop_name == '' {
		return '', 0
	}
	// Fortune only multiplies a drop that is not the block itself - an ore
	// dropping its own block gains nothing from it, exactly as in game.
	block_item := s.hub.data.item_for_block(block_id)
	if block_item != 0 && s.hub.data.item_name(block_item) == drop_name {
		return drop_name, drop_count
	}
	return drop_name, fortune_count(drop_count, s.held_enchantment_level('fortune'))
}

// PlayerEnchantTask puts an enchantment on a player's held item, on that
// player's own world runtime.
struct PlayerEnchantTask {
	runtime_id u64
	epoch      i64
	eid        int
	level      int
}

fn (t PlayerEnchantTask) name() string {
	return 'PlayerEnchantTask'
}

fn (t PlayerEnchantTask) run(mut tx worldrt.WorldTx) {
	mut target := player_for_epoch(mut tx, t.runtime_id, t.epoch) or { return }
	target.apply_held_enchantment(t.eid, t.level)
}

// apply_held_enchantment rewrites the held item's enchantments to include this
// one at this level, replacing whatever level it was at before.
fn (mut s NetworkSession) apply_held_enchantment(eid int, level int) {
	slot := s.player.held_slot()
	stack, net := s.inventory_stack_at(slot)
	if net == 0 || stack.count <= 0 {
		return
	}
	mut entries := item.enchantments_from_nbt(stack.raw_extra_data).filter(it.eid != eid)
	if level > 0 {
		entries << enchant.Applied{
			eid:   eid
			level: level
		}
	}
	mut updated := stack
	updated.raw_extra_data = item.enchanted_nbt(entries)
	s.player.put_stack(net, updated)
	wrapped := wrap_stack_id(updated, net)
	s.player.set_held(slot, wrapped)
	s.send_slot_update(slot, wrapped)
}

// enchant_held_item is the View entry point: it says what the named
// enchantment would do to what the player is holding, and applies it on that
// player's own world runtime when it can go there.
pub fn (mut s NetworkSession) enchant_held_item(name string, level int) player.EnchantResult {
	e := enchant.get_by_name(name) or { return .not_found }
	stack, held_name := s.held_stack_and_name()
	if held_name == '' || stack.count <= 0 {
		return .no_item
	}
	if !e.can_enchant(held_name) || level < e.min_level() || level > e.max_level() {
		return .cannot_combine
	}
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return .no_item
	}
	wr.submit(PlayerEnchantTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
		eid:        e.id()
		level:      level
	})
	return .applied
}

// held_item_name is the id of what the player is holding, for the callers that
// only need to name it.
pub fn (s &NetworkSession) held_item_name() string {
	_, name := s.held_stack_and_name()
	return name
}
