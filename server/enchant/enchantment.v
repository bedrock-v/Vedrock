module enchant

// Vanilla enchantment ids end below this; plugin enchantments allocate from
// here up, matching the PowerNukkitX scheme.
pub const custom_enchantment_id_start = 256

// Enchantment is the behaviour contract every enchantment implements. Vanilla
// enchantments and plugin ones share the same interface, so combat and armor
// code can query them uniformly.
pub interface Enchantment {
	// id returns the numeric enchantment id used in item NBT.
	id() int
	// name returns the identifier without namespace, e.g. 'sharpness'.
	name() string
	// min_level is the lowest valid level.
	min_level() int
	// max_level is the highest valid level.
	max_level() int
	// can_enchant reports whether the enchantment applies to the item id.
	can_enchant(item_id string) bool
	// attack_bonus is extra melee damage granted at level, 0 for non-offense.
	attack_bonus(level int) f32
	// protection_factor is the damage reduction weight at level, 0 for
	// non-armor enchantments.
	protection_factor(level int) f32
}

// SimpleEnchantment is the base class for enchantments that carry flat
// per-level bonuses and match items by id substring.
pub struct SimpleEnchantment {
pub:
	eid     int
	ident   string
	min_lvl int = 1
	max_lvl int = 1
	// item_match holds substrings an item id must contain, e.g. ['sword',
	// 'axe']. Empty matches every item.
	item_match           []string
	attack_per_level     f32
	protection_per_level f32
}

pub fn (e SimpleEnchantment) id() int {
	return e.eid
}

pub fn (e SimpleEnchantment) name() string {
	return e.ident
}

pub fn (e SimpleEnchantment) min_level() int {
	return e.min_lvl
}

pub fn (e SimpleEnchantment) max_level() int {
	return e.max_lvl
}

pub fn (e SimpleEnchantment) can_enchant(item_id string) bool {
	if e.item_match.len == 0 {
		return true
	}
	for m in e.item_match {
		if item_id.contains(m) {
			return true
		}
	}
	return false
}

pub fn (e SimpleEnchantment) attack_bonus(level int) f32 {
	if level <= 0 {
		return 0
	}
	return e.attack_per_level * f32(level)
}

pub fn (e SimpleEnchantment) protection_factor(level int) f32 {
	if level <= 0 {
		return 0
	}
	return e.protection_per_level * f32(level)
}
