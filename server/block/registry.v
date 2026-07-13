module block

// Registry maps block runtime ids and namespaced ids to their concrete Block
// class. The session layer holds one Registry and queries it for per-block
// behaviour (breakability, hardness, ...) instead of hard-coding runtime ids.
pub struct Registry {
mut:
	by_runtime map[int]Block
	by_name    map[string]Block
}

// new_registry builds a Registry pre-populated with the built-in block classes.
pub fn new_registry() Registry {
	mut r := Registry{}
	for b in default_blocks() {
		r.register(b)
	}
	return r
}

// register adds or overrides the class for a block.
pub fn (mut r Registry) register(b Block) {
	r.by_runtime[b.runtime_id()] = b
	r.by_name[b.identifier()] = b
}

// get returns the registered class for a runtime id, or none if unregistered.
pub fn (r &Registry) get(runtime_id int) ?Block {
	return r.by_runtime[runtime_id] or { return none }
}

// get_by_name returns the registered class for a namespaced id, or none if
// unregistered.
pub fn (r &Registry) get_by_name(id string) ?Block {
	return r.by_name[id] or { return none }
}

// breakable reports whether survival players may destroy the block with the
// given runtime id. Unregistered blocks fall back to breakable.
pub fn (r &Registry) breakable(runtime_id int) bool {
	if b := r.get(runtime_id) {
		return b.breakable()
	}
	return true
}

// hardness returns the break hardness for a runtime id, falling back to 1.0
// for unregistered blocks.
pub fn (r &Registry) hardness(runtime_id int) f32 {
	if b := r.get(runtime_id) {
		return b.hardness()
	}
	return 1.0
}

// len is the number of registered block classes.
pub fn (r &Registry) len() int {
	return r.by_name.len
}

// default_blocks is the built-in set of modelled blocks.
// Extend this list as new block classes are added.
fn default_blocks() []Block {
	mut result := [
		Block(new_stone_block()),
		new_dirt_block(),
		new_grass_block(),
		new_bedrock_block(),
		new_coal_ore(),
		new_iron_ore(),
		new_gold_ore(),
		new_diamond_ore(),
		new_emerald_ore(),
		new_copper_ore(),
		new_redstone_ore(),
		new_lapis_ore(),
		new_coal_block(),
		new_iron_block(),
		new_gold_block(),
		new_diamond_block(),
		new_emerald_block(),
		new_copper_block(),
		new_redstone_block(),
		new_lapis_block(),
		new_cobblestone(),
		new_sand(),
		new_red_sand(),
		new_gravel(),
		new_sandstone(),
		new_andesite(),
		new_polished_andesite(),
		new_diorite(),
		new_polished_diorite(),
		new_granite(),
		new_polished_granite(),
		new_netherrack(),
		new_end_stone(),
		new_obsidian(),
		new_ice(),
		new_snow(),
		new_clay(),
		new_mossy_cobblestone(),
		new_packed_ice(),
		new_blue_ice(),
		new_cobbled_deepslate(),
		new_tuff(),
		new_calcite(),
		new_smooth_basalt(),
		new_dripstone_block(),
	]
	result << wood_blocks()
	result << redstone_component_blocks()
	result << container_blocks()
	return result
}
