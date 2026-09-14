module block

// BlockLoot describes drops that differ from a block's normal item form.
// Blocks without custom loot are resolved through the block to item mapping.
//
// This only models simple count ranges. Tool requirements, enchantments,
// growth stages and full vanilla loot table behavior are not yet supported.
pub struct BlockLoot {
pub:
	item_name string
	min_count int = 1
	max_count int = 1
}

// loot_for_block returns the override loot for a block's namespaced
// identifier.
pub fn loot_for_block(identifier string) ?BlockLoot {
	if identifier == 'minecraft:stone' {
		return BlockLoot{
			item_name: 'minecraft:cobblestone'
		}
	}
	if identifier == 'minecraft:grass_block' {
		return BlockLoot{
			item_name: 'minecraft:dirt'
		}
	}
	if identifier == 'minecraft:coal_ore' {
		return BlockLoot{
			item_name: 'minecraft:coal'
		}
	}
	if identifier == 'minecraft:diamond_ore' {
		return BlockLoot{
			item_name: 'minecraft:diamond'
		}
	}
	if identifier == 'minecraft:emerald_ore' {
		return BlockLoot{
			item_name: 'minecraft:emerald'
		}
	}
	if identifier == 'minecraft:redstone_ore' {
		return BlockLoot{
			item_name: 'minecraft:redstone'
			min_count: 4
			max_count: 5
		}
	}
	if identifier == 'minecraft:lapis_ore' {
		return BlockLoot{
			item_name: 'minecraft:lapis_lazuli'
			min_count: 4
			max_count: 9
		}
	}
	if identifier == 'minecraft:iron_ore' {
		return BlockLoot{
			item_name: 'minecraft:raw_iron'
		}
	}
	if identifier == 'minecraft:gold_ore' {
		return BlockLoot{
			item_name: 'minecraft:raw_gold'
		}
	}
	if identifier == 'minecraft:copper_ore' {
		return BlockLoot{
			item_name: 'minecraft:raw_copper'
			min_count: 2
			max_count: 5
		}
	}
	return none
}

// BlockExperience is the range of experience a block leaves when it is mined
// without silk touch.
pub struct BlockExperience {
pub:
	min_amount int
	max_amount int
}

// experience_for_block returns what mining a block is worth. Only the ores
// that carry experience in game have any; everything else has none.
pub fn experience_for_block(identifier string) ?BlockExperience {
	return match identifier {
		'minecraft:coal_ore', 'minecraft:deepslate_coal_ore' { BlockExperience{0, 2} }
		'minecraft:diamond_ore', 'minecraft:deepslate_diamond_ore' { BlockExperience{3, 7} }
		'minecraft:emerald_ore', 'minecraft:deepslate_emerald_ore' { BlockExperience{3, 7} }
		'minecraft:lapis_ore', 'minecraft:deepslate_lapis_ore' { BlockExperience{2, 5} }
		'minecraft:redstone_ore', 'minecraft:deepslate_redstone_ore' { BlockExperience{1, 5} }
		'minecraft:nether_gold_ore' { BlockExperience{0, 1} }
		'minecraft:nether_quartz_ore' { BlockExperience{2, 5} }
		else { none }
	}
}
