module session

import server.item
import server.block
import server.entity
import server.enchant

// register_custom_item registers a data-driven item definition, allocates its
// runtime id and exposes it to the item class registry and the numeric id
// lookup so inventories and creative content resolve it like a vanilla item.
pub fn (mut h Hub) register_custom_item(def item.CustomItemDefinition) int {
	rid := h.custom_items.register(def)
	mut stored := def
	stored.runtime_id = rid
	h.items.register(item.CustomItemClass{
		def: stored
	})
	h.data.item_id_by_name[stored.id] = rid
	return rid
}

// register_custom_block registers a data-driven block definition, allocates
// its runtime id and adds a matching block class so gameplay lookups
// (hardness, identifiers) work server-side.
pub fn (mut h Hub) register_custom_block(def block.CustomBlockDefinition) int {
	rid := h.custom_blocks.register(def)
	h.blocks.register(block.SimpleBlock{
		id:             def.id
		block_runtime:  rid
		break_hardness: def.break_hardness
	})
	return rid
}

// register_custom_entity registers a custom entity type: the definition goes
// into the AvailableActorIdentifiers list and the factory into the entity
// registry under the definition's short name, so /summon and spawn_entity
// work with it.
pub fn (mut h Hub) register_custom_entity(def entity.CustomEntityDefinition, factory fn () entity.Behaviour) bool {
	if !h.custom_entities.register(def) {
		return false
	}
	h.entity_registry.register(def.short_name(), factory)
	return true
}

// register_enchantment adds an enchantment to the shared registry, returning
// false when its id or name is already taken.
pub fn (mut h Hub) register_enchantment(e enchant.Enchantment) bool {
	return h.enchantments.register(e)
}

// next_enchantment_id returns the next free id in the custom enchantment
// range.
pub fn (mut h Hub) next_enchantment_id() int {
	return h.enchantments.next_custom_id()
}

pub fn (mut h Hub) custom_item_names() []string {
	return h.custom_items.names()
}

pub fn (mut h Hub) custom_block_names() []string {
	return h.custom_blocks.names()
}

pub fn (mut h Hub) custom_entity_names() []string {
	return h.custom_entities.names()
}
