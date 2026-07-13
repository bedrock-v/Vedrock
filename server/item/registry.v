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
	mut items := []Item{}
	items << Item(new_apple())
	items << new_bread()
	items << new_cooked_beef()
	items << new_golden_apple()
	items << new_potion_item()
	items << new_carrot()
	items << new_cooked_chicken()
	items << new_stone_item()
	items << new_dirt_item()
	items << new_grass_block_item()
	items << new_bedrock_item()
	items << new_stick()

	for tier in [ToolTier.wood, .stone, .iron, .gold, .diamond, .netherite] {
		for typ in [ToolType.sword, .pickaxe, .axe, .shovel, .hoe] {
			items << new_tool_item(tier, typ)
		}
	}

	for tier in [ArmorTier.leather, .gold, .iron, .diamond, .netherite] {
		for slot in [ArmorSlot.helmet, .chestplate, .leggings, .boots] {
			items << new_armor_item(tier, slot)
		}
	}

	items << new_porkchop()
	items << new_cooked_porkchop()
	items << new_beef()
	items << new_chicken()
	items << new_mutton()
	items << new_cooked_mutton()
	items << new_salmon()
	items << new_cooked_salmon()
	items << new_cod()
	items << new_cooked_cod()
	items << new_melon_slice()
	items << new_pumpkin_pie()
	items << new_cake()
	items << new_mushroom_stew()
	items << new_rabbit_stew()
	items << new_beetroot_soup()
	items << new_baked_potato()
	items << new_potato()
	items << new_beetroot()
	items << new_sweet_berries()
	items << new_glow_berries()
	items << new_dried_kelp()
	items << new_honey_bottle()

	items << new_raw_iron()
	items << new_raw_gold()
	items << new_raw_copper()
	items << new_iron_ingot()
	items << new_gold_ingot()
	items << new_copper_ingot()
	items << new_coal()
	items << new_diamond()
	items << new_emerald()
	items << new_redstone()
	items << new_lapis_lazuli()
	items << new_coal_ore_item()
	items << new_iron_ore_item()
	items << new_gold_ore_item()
	items << new_diamond_ore_item()
	items << new_emerald_ore_item()
	items << new_copper_ore_item()
	items << new_redstone_ore_item()
	items << new_lapis_ore_item()
	items << new_coal_block_item()
	items << new_iron_block_item()
	items << new_gold_block_item()
	items << new_diamond_block_item()
	items << new_emerald_block_item()
	items << new_copper_block_item()
	items << new_redstone_block_item()
	items << new_lapis_block_item()

	items << new_cobblestone_item()
	items << new_sand_item()
	items << new_red_sand_item()
	items << new_gravel_item()
	items << new_sandstone_item()
	items << new_andesite_item()
	items << new_polished_andesite_item()
	items << new_diorite_item()
	items << new_polished_diorite_item()
	items << new_granite_item()
	items << new_polished_granite_item()
	items << new_netherrack_item()
	items << new_end_stone_item()
	items << new_obsidian_item()
	items << new_ice_item()
	items << new_snow_item()
	items << new_clay_item()
	items << new_mossy_cobblestone_item()
	items << new_packed_ice_item()
	items << new_blue_ice_item()
	items << new_cobbled_deepslate_item()
	items << new_tuff_item()
	items << new_calcite_item()
	items << new_smooth_basalt_item()
	items << new_dripstone_block_item()
	items << wood_items()
	items << redstone_component_items()

	return items
}
