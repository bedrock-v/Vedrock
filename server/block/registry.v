module block

import server.world

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

// default_blocks is the built-in set of modelled blocks. Extend this list as
// new block classes gain behaviour; everything else falls back to SimpleBlock.
fn default_blocks() []Block {
	return [
		Block(SimpleBlock{
			id:             'minecraft:stone'
			block_runtime:  world.stone.network_id
			break_hardness: 1.5
		}),
		SimpleBlock{
			id:             'minecraft:dirt'
			block_runtime:  world.dirt.network_id
			break_hardness: 0.5
		},
		SimpleBlock{
			id:             'minecraft:grass_block'
			block_runtime:  world.grass_block.network_id
			break_hardness: 0.6
		},
		UnbreakableBlock{
			id:            'minecraft:bedrock'
			block_runtime: world.bedrock.network_id
		},
	]
}
