module world

pub const flat_spawn_y = -60
pub const void_spawn_y = 64
pub const normal_base_y = -60
pub const normal_height_variation = 7

pub interface Generator {
	spawn_y() int
	uses_blocks() bool
	generate(chunk_x int, chunk_z int) Chunk
	block_at(x int, y int, z int) int
}

pub struct VoidGenerator {
	dim Dimension = overworld
}

pub fn (g VoidGenerator) spawn_y() int {
	return void_spawn_y
}

pub fn (g VoidGenerator) uses_blocks() bool {
	return false
}

pub fn (g VoidGenerator) generate(chunk_x int, chunk_z int) Chunk {
	return new_chunk_dim(g.dim)
}

pub fn (g VoidGenerator) block_at(x int, y int, z int) int {
	return air.network_id
}

// fill_flat_layers fills every column of c with blocks bottom up starting at
// base_y.
fn fill_flat_layers(mut c Chunk, base_y int, layers []Block) {
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for i, b in layers {
				c.set_block(x, base_y + i, z, b)
			}
		}
	}
}

// flat_layer_at is fill_flat_layers' block_at counterpart.
fn flat_layer_at(y int, base_y int, layers []Block) int {
	offset := y - base_y
	if offset < 0 || offset >= layers.len {
		return air.network_id
	}
	return layers[offset].network_id
}

pub struct FlatGenerator {
	dim Dimension = overworld
}

fn (g FlatGenerator) layers() []Block {
	return [bedrock, dirt, dirt, grass_block]
}

pub fn (g FlatGenerator) spawn_y() int {
	return g.dim.min_y + g.layers().len
}

pub fn (g FlatGenerator) uses_blocks() bool {
	return true
}

pub fn (g FlatGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	fill_flat_layers(mut c, g.dim.min_y, g.layers())
	return c
}

pub fn (g FlatGenerator) block_at(x int, y int, z int) int {
	return flat_layer_at(y, g.dim.min_y, g.layers())
}

pub struct NetherGenerator {
	dim Dimension = nether
}

fn (g NetherGenerator) layers() []Block {
	return [bedrock, netherrack, netherrack, netherrack]
}

pub fn (g NetherGenerator) spawn_y() int {
	return g.dim.min_y + g.layers().len
}

pub fn (g NetherGenerator) uses_blocks() bool {
	return true
}

pub fn (g NetherGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	fill_flat_layers(mut c, g.dim.min_y, g.layers())
	g.fill_ceiling(mut c)
	return c
}

fn (g NetherGenerator) fill_ceiling(mut c Chunk) {
	roof_y := g.dim.max_y()
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			c.set_block(x, roof_y, z, bedrock)
		}
	}
}

pub fn (g NetherGenerator) block_at(x int, y int, z int) int {
	if y == g.dim.max_y() {
		return bedrock.network_id
	}
	return flat_layer_at(y, g.dim.min_y, g.layers())
}

const end_platform_size = 5

pub struct EndGenerator {
	dim Dimension = the_end
}

fn (g EndGenerator) layers() []Block {
	return [bedrock, end_stone, end_stone, end_stone]
}

pub fn (g EndGenerator) spawn_y() int {
	return g.dim.min_y + g.layers().len
}

pub fn (g EndGenerator) uses_blocks() bool {
	return true
}

pub fn (g EndGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	fill_flat_layers(mut c, g.dim.min_y, g.layers())
	if chunk_x == 0 && chunk_z == 0 {
		g.place_spawn_platform(mut c)
	}
	return c
}

fn (g EndGenerator) place_spawn_platform(mut c Chunk) {
	platform_y := g.dim.min_y + g.layers().len
	for x in 0 .. end_platform_size {
		for z in 0 .. end_platform_size {
			c.set_block(x, platform_y, z, obsidian)
		}
	}
}

pub fn (g EndGenerator) block_at(x int, y int, z int) int {
	platform_y := g.dim.min_y + g.layers().len
	if y == platform_y && x >= 0 && x < end_platform_size && z >= 0 && z < end_platform_size {
		return obsidian.network_id
	}
	return flat_layer_at(y, g.dim.min_y, g.layers())
}

pub struct NormalGenerator {
	dim Dimension = overworld
}

pub fn (g NormalGenerator) spawn_y() int {
	return g.surface_height(0, 0) + 1
}

pub fn (g NormalGenerator) uses_blocks() bool {
	return true
}

pub fn (g NormalGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			height := g.surface_height(chunk_x * 16 + x, chunk_z * 16 + z)
			for y in g.dim.min_y .. height {
				c.set_block(x, y, z, stone)
			}
			c.set_block(x, height, z, grass_block)
		}
	}
	return c
}

pub fn (g NormalGenerator) block_at(x int, y int, z int) int {
	height := g.surface_height(x, z)
	return match true {
		y >= g.dim.min_y && y < height { stone.network_id }
		y == height { grass_block.network_id }
		else { air.network_id }
	}
}

fn (g NormalGenerator) surface_height(world_x int, world_z int) int {
	mut b := []u8{}
	put_u32_le(mut b, u32(world_x))
	put_u32_le(mut b, u32(world_z))
	return g.dim.min_y + 4 + int(fnv1a_32(b) % u32(normal_height_variation))
}

pub fn new_generator(name string) Generator {
	mut g := Generator(FlatGenerator{})
	match name.to_lower() {
		'void' { g = VoidGenerator{} }
		'normal' { g = NormalGenerator{} }
		else {}
	}

	return g
}

pub fn generate_flat() Chunk {
	return FlatGenerator{}.generate(0, 0)
}

pub fn generate_void() Chunk {
	return VoidGenerator{}.generate(0, 0)
}

// GeneratorFactory builds a fresh Generator sized for dim. Each lookup gets
// its own instance, mirroring entity.Registry's BehaviourFactory.
pub type GeneratorFactory = fn (dim Dimension) Generator

pub struct GeneratorRegistry {
mut:
	factories map[string]GeneratorFactory
}

pub fn new_generator_registry() GeneratorRegistry {
	mut r := GeneratorRegistry{}
	r.register('void', fn (dim Dimension) Generator {
		return VoidGenerator{
			dim: dim
		}
	})
	r.register('flat', fn (dim Dimension) Generator {
		return FlatGenerator{
			dim: dim
		}
	})
	r.register('normal', fn (dim Dimension) Generator {
		return NormalGenerator{
			dim: dim
		}
	})
	r.register('nether', fn (dim Dimension) Generator {
		return NetherGenerator{
			dim: dim
		}
	})
	r.register('end', fn (dim Dimension) Generator {
		return EndGenerator{
			dim: dim
		}
	})
	return r
}

pub fn (mut r GeneratorRegistry) register(name string, factory GeneratorFactory) {
	r.factories[name.to_lower()] = factory
}
pub fn (r &GeneratorRegistry) create(name string, dim Dimension) ?Generator {
	factory := r.factories[name.to_lower()] or { return none }
	return factory(dim)
}

pub fn (r &GeneratorRegistry) names() []string {
	mut out := []string{cap: r.factories.len}
	for name, _ in r.factories {
		out << name
	}
	return out
}
