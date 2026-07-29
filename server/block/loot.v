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
