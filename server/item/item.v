module item

// Item is the behaviour contract every item class implements. Every item is
// its own class built on a family base struct (ToolItem, ArmorItem, FoodItem,
// BlockItem, SimpleItem) and registered in the Registry so the session layer
// can look it up by its string identifier (e.g. 'minecraft:diamond_sword').
pub interface Item {
	// identifier returns the namespaced item id used on the wire.
	identifier() string
	// max_stack_size is how many of this item fit in a single slot.
	max_stack_size() int
	// attack_damage is the melee damage dealt on hit, 0 for non-weapons.
	attack_damage() f32
	// nutrition is the hunger points restored on eat, 0 for non-food.
	nutrition() int
	// saturation is the saturation modifier applied on eat, 0 for non-food.
	saturation() f32
	// block_runtime_id is the block placed on use, 0 for non-block items.
	block_runtime_id() int
	// durability is the max number of uses before the item breaks, 0 for
	// items that don't take durability damage.
	durability() int
	// mining_speed is the block breaking speed multiplier this item grants
	// as a tool, 1.0 (no bonus) for non-tools.
	mining_speed() f32
	// armor_points is the defense value this item grants when worn, 0 for
	// non-armor.
	armor_points() int
}

// SimpleItem is the base class for items that carry no special behaviour
// (dyes, sticks, string, ...). Concrete simple items embed it and fill in
// their identity; anything unregistered behaves like a default SimpleItem.
pub struct SimpleItem {
pub:
	id        string
	stack_max int = 64
}

pub fn (i SimpleItem) identifier() string {
	return i.id
}

pub fn (i SimpleItem) max_stack_size() int {
	return i.stack_max
}

pub fn (i SimpleItem) attack_damage() f32 {
	return 0
}

pub fn (i SimpleItem) nutrition() int {
	return 0
}

pub fn (i SimpleItem) saturation() f32 {
	return 0
}

pub fn (i SimpleItem) block_runtime_id() int {
	return 0
}

pub fn (i SimpleItem) durability() int {
	return 0
}

pub fn (i SimpleItem) mining_speed() f32 {
	return 1.0
}

pub fn (i SimpleItem) armor_points() int {
	return 0
}
