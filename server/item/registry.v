module item

// Registry maps namespaced item ids to their concrete Item class. The session
// layer holds one Registry and queries it for per-item behaviour (stack size,
// attack damage, ...) instead of hard-coding numeric ids.
pub struct Registry {
mut:
	items map[string]Item
}

// new_registry builds a Registry pre-populated with the built-in item classes.
pub fn new_registry() Registry {
	mut r := Registry{}
	for it in default_items() {
		r.register(it)
	}
	return r
}

// register adds or overrides the class for an item id.
pub fn (mut r Registry) register(it Item) {
	r.items[it.identifier()] = it
}

// get returns the registered class for id, or none if unregistered.
pub fn (r &Registry) get(id string) ?Item {
	return r.items[id] or { return none }
}

// max_stack_size returns the stack size for id, falling back to 64 for
// unregistered items.
pub fn (r &Registry) max_stack_size(id string) int {
	if it := r.get(id) {
		return it.max_stack_size()
	}
	return 64
}

pub fn (r &Registry) consume_result(id string, meta int) ?ConsumeResult {
	it := r.get(id) or { return none }
	if it is PotionItem {
		return it.consume_result(meta)
	}
	return none
}

// len is the number of registered item classes.
pub fn (r &Registry) len() int {
	return r.items.len
}

// default_items is the built-in set of modelled items, one class per item.
// Extend this list as new item classes are added.
fn default_items() []Item {
	return [
		Item(new_diamond_sword()),
		new_iron_sword(),
		new_apple(),
		new_bread(),
		new_cooked_beef(),
		new_golden_apple(),
		new_potion_item(),
		new_carrot(),
		new_cooked_chicken(),
		new_stone_item(),
		new_dirt_item(),
		new_grass_block_item(),
		new_bedrock_item(),
		new_stick(),
	]
}
