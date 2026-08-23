module item

// Non-block items of the combat and progression family; the block items live
// in server/block/combat_progression_item.v.

// DurabilityItem is the base class for held combat items whose only shared
// behaviour is "takes durability damage, one per slot"; unlike ToolItem/
// ArmorItem there's no tier x shape matrix here (shield/bow/crossbow/trident
// are each one-off items).
pub struct DurabilityItem {
pub:
	id             string
	damage         f32
	max_durability int
}

pub fn (i DurabilityItem) identifier() string {
	return i.id
}

pub fn (i DurabilityItem) max_stack_size() int {
	return 1
}

pub fn (i DurabilityItem) attack_damage() f32 {
	return i.damage
}

pub fn (i DurabilityItem) nutrition() int {
	return 0
}

pub fn (i DurabilityItem) saturation() f32 {
	return 0
}

pub fn (i DurabilityItem) block_runtime_id() int {
	return 0
}

pub fn (i DurabilityItem) durability() int {
	return i.max_durability
}

pub fn (i DurabilityItem) mining_speed() f32 {
	return 1.0
}

pub fn (i DurabilityItem) armor_points() int {
	return 0
}

pub fn combat_progression_items() []Item {
	mut result := []Item{}
	result << Item(DurabilityItem{
		id:             'minecraft:shield'
		max_durability: 336
	})
	result << DurabilityItem{
		id:             'minecraft:bow'
		max_durability: 384
	}
	result << DurabilityItem{
		id:             'minecraft:crossbow'
		max_durability: 465
	}
	result << DurabilityItem{
		id:             'minecraft:trident'
		damage:         9
		max_durability: 250
	}
	result << DurabilityItem{
		id:             'minecraft:shears'
		max_durability: 238
	}

	result << SimpleItem{
		id: 'minecraft:arrow'
	}
	result << SimpleItem{
		id:        'minecraft:totem_of_undying'
		stack_max: 1
	}
	result << SimpleItem{
		id: 'minecraft:experience_bottle'
	}
	result << SimpleItem{
		id: 'minecraft:glass_bottle'
	}
	// Splash/lingering potions carry the same per meta potion effect data as
	// minecraft:potion (see potion.v), but applying that effect happens by
	// throwing the item as a projectile.
	result << SimpleItem{
		id:        'minecraft:splash_potion'
		stack_max: 1
	}
	result << SimpleItem{
		id:        'minecraft:lingering_potion'
		stack_max: 1
	}
	return result
}
