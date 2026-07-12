module item

// ToolTier is the material tier shared by every tool and weapon.
pub enum ToolTier {
	wood
	stone
	iron
	gold
	diamond
	netherite
}

// ToolType is the tool/weapon shape. Attack damage differs by type; mining
// speed and durability are tier-only (same across all five shapes).
pub enum ToolType {
	sword
	pickaxe
	axe
	shovel
	hoe
}

// ToolItem is the class for every tier x type combination (e.g. tier
// .diamond, tool_type .pickaxe -> 'minecraft:diamond_pickaxe'). One
// parametrized struct instead of 30 near-identical classes, since nothing
// about a tool's behaviour is unique per material - it's entirely tier+type
// data (see ITEMS_BLOCKS.md open question 1).
pub struct ToolItem {
pub:
	id             string
	tier           ToolTier
	tool_type      ToolType
	damage         f32
	max_durability int
	speed          f32
}

pub fn (i ToolItem) identifier() string {
	return i.id
}

pub fn (i ToolItem) max_stack_size() int {
	return 1
}

pub fn (i ToolItem) attack_damage() f32 {
	return i.damage
}

pub fn (i ToolItem) nutrition() int {
	return 0
}

pub fn (i ToolItem) saturation() f32 {
	return 0
}

pub fn (i ToolItem) block_runtime_id() int {
	return 0
}

pub fn (i ToolItem) durability() int {
	return i.max_durability
}

pub fn (i ToolItem) mining_speed() f32 {
	return i.speed
}

pub fn (i ToolItem) armor_points() int {
	return 0
}

// prefix is the item id prefix vanilla uses for this tier ('wooden' and
// 'golden' are irregular, the rest match the enum name verbatim).
fn (t ToolTier) prefix() string {
	return match t {
		.wood { 'wooden' }
		.stone { 'stone' }
		.iron { 'iron' }
		.gold { 'golden' }
		.diamond { 'diamond' }
		.netherite { 'netherite' }
	}
}

fn (t ToolTier) tool_durability() int {
	return match t {
		.wood { 59 }
		.stone { 131 }
		.iron { 250 }
		.gold { 32 }
		.diamond { 1561 }
		.netherite { 2031 }
	}
}

fn (t ToolTier) tool_mining_speed() f32 {
	return match t {
		.wood { 2.0 }
		.stone { 4.0 }
		.iron { 6.0 }
		.gold { 12.0 }
		.diamond { 8.0 }
		.netherite { 9.0 }
	}
}

fn (t ToolType) suffix() string {
	return match t {
		.sword { 'sword' }
		.pickaxe { 'pickaxe' }
		.axe { 'axe' }
		.shovel { 'shovel' }
		.hoe { 'hoe' }
	}
}

fn attack_damage_for(tier ToolTier, typ ToolType) f32 {
	return match typ {
		.sword {
			match tier {
				.wood, .gold { f32(4.0) }
				.stone { f32(5.0) }
				.iron { f32(6.0) }
				.diamond { f32(7.0) }
				.netherite { f32(8.0) }
			}
		}
		.pickaxe {
			match tier {
				.wood, .gold { f32(2.0) }
				.stone { f32(3.0) }
				.iron { f32(4.0) }
				.diamond { f32(5.0) }
				.netherite { f32(6.0) }
			}
		}
		.axe {
			match tier {
				.wood, .gold { f32(7.0) }
				.stone, .iron, .diamond { f32(9.0) }
				.netherite { f32(10.0) }
			}
		}
		.shovel {
			match tier {
				.wood, .gold { f32(2.5) }
				.stone { f32(3.5) }
				.iron { f32(4.5) }
				.diamond { f32(5.5) }
				.netherite { f32(6.5) }
			}
		}
		.hoe {
			// All hoe tiers deal the same minimal melee damage in current
			// vanilla; hoes are a farming tool, not a weapon.
			f32(1.0)
		}
	}
}

// new_tool_item builds the class for a tier x tool-type combination.
pub fn new_tool_item(tier ToolTier, typ ToolType) ToolItem {
	return ToolItem{
		id:             'minecraft:${tier.prefix()}_${typ.suffix()}'
		tier:           tier
		tool_type:      typ
		damage:         attack_damage_for(tier, typ)
		max_durability: tier.tool_durability()
		speed:          tier.tool_mining_speed()
	}
}
