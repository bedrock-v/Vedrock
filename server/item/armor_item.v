module item

// ArmorTier is the material tier shared by every armor piece.
pub enum ArmorTier {
	leather
	gold
	copper
	iron
	diamond
	netherite
}

// ArmorSlot is the equipment slot an armor piece occupies.
pub enum ArmorSlot {
	helmet
	chestplate
	leggings
	boots
}

// ArmorItem is the class for every tier x slot combination (e.g. tier
// .diamond, slot .chestplate -> 'minecraft:diamond_chestplate'). One
// parametrized struct rather than 20 near-identical classes, same reasoning
// as ToolItem.
pub struct ArmorItem {
pub:
	id             string
	tier           ArmorTier
	slot           ArmorSlot
	defense        int
	max_durability int
}

pub fn (i ArmorItem) identifier() string {
	return i.id
}

pub fn (i ArmorItem) max_stack_size() int {
	return 1
}

pub fn (i ArmorItem) attack_damage() f32 {
	return 0
}

pub fn (i ArmorItem) nutrition() int {
	return 0
}

pub fn (i ArmorItem) saturation() f32 {
	return 0
}

pub fn (i ArmorItem) block_runtime_id() int {
	return 0
}

pub fn (i ArmorItem) durability() int {
	return i.max_durability
}

pub fn (i ArmorItem) mining_speed() f32 {
	return 1.0
}

pub fn (i ArmorItem) armor_points() int {
	return i.defense
}

// prefix is the item id prefix vanilla uses for this tier ('golden' is
// irregular, the rest match the enum name verbatim).
fn (t ArmorTier) prefix() string {
	return match t {
		.leather { 'leather' }
		.gold { 'golden' }
		.copper { 'copper' }
		.iron { 'iron' }
		.diamond { 'diamond' }
		.netherite { 'netherite' }
	}
}

fn (s ArmorSlot) suffix() string {
	return match s {
		.helmet { 'helmet' }
		.chestplate { 'chestplate' }
		.leggings { 'leggings' }
		.boots { 'boots' }
	}
}

fn defense_for(tier ArmorTier, slot ArmorSlot) int {
	return match tier {
		.leather {
			match slot {
				.helmet { 1 }
				.chestplate { 3 }
				.leggings { 2 }
				.boots { 1 }
			}
		}
		.gold {
			match slot {
				.helmet { 2 }
				.chestplate { 5 }
				.leggings { 3 }
				.boots { 1 }
			}
		}
		.copper {
			match slot {
				.helmet { 2 }
				.chestplate { 4 }
				.leggings { 3 }
				.boots { 1 }
			}
		}
		.iron {
			match slot {
				.helmet { 2 }
				.chestplate { 6 }
				.leggings { 5 }
				.boots { 2 }
			}
		}
		.diamond, .netherite {
			match slot {
				.helmet { 3 }
				.chestplate { 8 }
				.leggings { 6 }
				.boots { 3 }
			}
		}
	}
}

fn durability_for(tier ArmorTier, slot ArmorSlot) int {
	return match tier {
		.leather {
			match slot {
				.helmet { 55 }
				.chestplate { 80 }
				.leggings { 75 }
				.boots { 65 }
			}
		}
		.gold {
			match slot {
				.helmet { 77 }
				.chestplate { 112 }
				.leggings { 105 }
				.boots { 91 }
			}
		}
		.copper {
			match slot {
				.helmet { 122 }
				.chestplate { 177 }
				.leggings { 166 }
				.boots { 143 }
			}
		}
		.iron {
			match slot {
				.helmet { 165 }
				.chestplate { 240 }
				.leggings { 225 }
				.boots { 195 }
			}
		}
		.diamond {
			match slot {
				.helmet { 363 }
				.chestplate { 528 }
				.leggings { 495 }
				.boots { 429 }
			}
		}
		.netherite {
			match slot {
				.helmet { 407 }
				.chestplate { 592 }
				.leggings { 555 }
				.boots { 481 }
			}
		}
	}
}

// new_armor_item builds the class for a tier x slot combination.
pub fn new_armor_item(tier ArmorTier, slot ArmorSlot) ArmorItem {
	return ArmorItem{
		id:             'minecraft:${tier.prefix()}_${slot.suffix()}'
		tier:           tier
		slot:           slot
		defense:        defense_for(tier, slot)
		max_durability: durability_for(tier, slot)
	}
}
