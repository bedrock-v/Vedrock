module item

import server.world

// Registry maps namespaced item ids to their concrete Item class. The session
// layer holds one Registry and queries it for per-item behaviour (stack size,
// sword damage, ...) instead of hard-coding numeric ids.
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

// len is the number of registered item classes.
pub fn (r &Registry) len() int {
	return r.items.len
}

// default_items is the built-in set of modelled items. Extend this list as new
// item classes gain behaviour; everything else falls back to SimpleItem.
fn default_items() []Item {
	return [
		Item(SwordItem{
			id:            'minecraft:diamond_sword'
			attack_damage: 7
			durability:    1561
		}),
		SwordItem{
			id:            'minecraft:iron_sword'
			attack_damage: 6
			durability:    250
		},
		FoodItem{
			id:         'minecraft:apple'
			nutrition:  4
			saturation: 2.4
		},
		FoodItem{
			id:         'minecraft:bread'
			nutrition:  5
			saturation: 6.0
		},
		FoodItem{
			id:         'minecraft:cooked_beef'
			nutrition:  8
			saturation: 12.8
		},
		FoodItem{
			id:         'minecraft:golden_apple'
			nutrition:  4
			saturation: 9.6
		},
		FoodItem{
			id:         'minecraft:carrot'
			nutrition:  3
			saturation: 3.6
		},
		FoodItem{
			id:         'minecraft:cooked_chicken'
			nutrition:  6
			saturation: 7.2
		},
		BlockItem{
			id:               'minecraft:stone'
			block_runtime_id: world.stone.network_id
		},
		BlockItem{
			id:               'minecraft:dirt'
			block_runtime_id: world.dirt.network_id
		},
		BlockItem{
			id:               'minecraft:grass_block'
			block_runtime_id: world.grass_block.network_id
		},
		BlockItem{
			id:               'minecraft:bedrock'
			block_runtime_id: world.bedrock.network_id
		},
		SimpleItem{
			id: 'minecraft:stick'
		},
	]
}
