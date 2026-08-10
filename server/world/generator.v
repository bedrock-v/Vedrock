module world

pub interface Generator {
	spawn_y() int
	uses_blocks() bool
	generate(chunk_x int, chunk_z int) Chunk
	block_at(x int, y int, z int) int
	biome_at(x int, z int) int
}

fn spawn_body_clear(id int) bool {
	return id == air.network_id
}

fn spawn_floor_solid(id int) bool {
	return id != air.network_id && id != water.network_id && id != lava.network_id
}

fn safe_spawn_y(g Generator, dim Dimension, x int, z int, preferred int) int {
	min_y := dim.min_y + 1
	max_y := dim.max_y() - 1
	mut start := preferred
	if start < min_y {
		start = min_y
	}
	if start > max_y {
		start = max_y
	}
	for y in start .. max_y + 1 {
		if spawn_floor_solid(g.block_at(x, y - 1, z)) && spawn_body_clear(g.block_at(x, y, z))
			&& spawn_body_clear(g.block_at(x, y + 1, z)) {
			return y
		}
	}
	for y := start - 1; y >= min_y; y-- {
		if spawn_floor_solid(g.block_at(x, y - 1, z)) && spawn_body_clear(g.block_at(x, y, z))
			&& spawn_body_clear(g.block_at(x, y + 1, z)) {
			return y
		}
	}
	return start
}

// ---- Nether ----
//
// The Nether generator is intentionally compact: bedrock shell, a lava sea,
// rough lower and upper netherrack masses, and a wide traversable middle cavern.
// Extra nether biomes, structures, netherite and portals are out of scope.
pub const nether_lava_level = 31
const nether_spawn_floor_y = 63
const nether_floor_salt = u32(401)
const nether_ceiling_salt = u32(409)
const nether_density_salt = u32(419)
const nether_detail_salt = u32(421)
const nether_surface_salt = u32(431)
const nether_glowstone_salt = u32(457)
const density_cell_xz = 4
const density_cell_y = 8
const density_grid_xz = 5
const density_grid_y = 17

pub struct NetherGenerator {
	dim Dimension = nether
}

pub fn (g NetherGenerator) spawn_y() int {
	return safe_spawn_y(g, g.dim, 0, 0, nether_spawn_floor_y + 1)
}

pub fn (g NetherGenerator) uses_blocks() bool {
	return true
}

fn (g NetherGenerator) spawn_override(x int, y int, z int) ?int {
	if x < -2 || x > 2 || z < -2 || z > 2 {
		return none
	}
	if y > g.dim.min_y + 4 && y <= nether_spawn_floor_y {
		return netherrack.network_id
	}
	if y > nether_spawn_floor_y && y <= nether_spawn_floor_y + 3 {
		return air.network_id
	}
	return none
}

fn (g NetherGenerator) floor_bedrock_at(x int, y int, z int) bool {
	if y == g.dim.min_y {
		return true
	}
	if y > g.dim.min_y + 4 {
		return false
	}
	threshold := 0.70 - f64(y - g.dim.min_y) * 0.13
	return hash3_unit(x, y, z, nether_floor_salt + 17) < threshold
}

fn (g NetherGenerator) roof_bedrock_at(x int, y int, z int) bool {
	roof_y := g.dim.max_y()
	if y == roof_y {
		return true
	}
	if y < roof_y - 4 || y == roof_y - 1 {
		return false
	}
	threshold := 0.28 + f64(y - (roof_y - 4)) * 0.12
	return hash3_unit(x, y, z, nether_ceiling_salt + 29) < threshold
}

fn f64_clamp(v f64, min f64, max f64) f64 {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

fn lerp_f64(a f64, b f64, t f64) f64 {
	return a + (b - a) * t
}

fn density_grid_index(gx int, gy int, gz int) int {
	return (gx * density_grid_y + gy) * density_grid_xz + gz
}

fn (g NetherGenerator) density_at(x int, y int, z int) f64 {
	main := (fbm3d(f64(x) / 38.0, f64(y) / 28.0, f64(z) / 38.0, nether_density_salt, 4) - 0.5) * 2.0
	detail := (fbm3d(f64(x) / 16.0, f64(y) / 14.0, f64(z) / 16.0, nether_detail_salt, 2) - 0.5) * 0.65
	lower := f64_clamp((38.0 - f64(y)) / 28.0, 0.0, 1.0) * 1.35
	upper := f64_clamp((f64(y) - 82.0) / 32.0, 0.0, 1.0) * 1.35
	middle_open := 0.22 + f64_clamp((f64(y) - 38.0) / 26.0, 0.0, 1.0) * 0.10
	return main + detail + lower + upper - middle_open
}

// build_density_grid samples one chunk's noise on a coarse lattice. Sampling
// every block is far too expensive, so the columns in between are recovered
// with density_from_grid's trilinear interpolation.
fn build_density_grid(base_x int, base_z int, sample fn (x int, y int, z int) f64) []f64 {
	mut grid := []f64{len: density_grid_xz * density_grid_y * density_grid_xz}
	for gx in 0 .. density_grid_xz {
		world_x := base_x + gx * density_cell_xz
		for gy in 0 .. density_grid_y {
			y := gy * density_cell_y
			for gz in 0 .. density_grid_xz {
				world_z := base_z + gz * density_cell_xz
				grid[density_grid_index(gx, gy, gz)] = sample(world_x, y, world_z)
			}
		}
	}
	return grid
}

fn (g NetherGenerator) density_grid(base_x int, base_z int) []f64 {
	return build_density_grid(base_x, base_z, fn [g] (x int, y int, z int) f64 {
		return g.density_at(x, y, z)
	})
}

// fill_density_column resolves the horizontal half of the interpolation once
// for a whole column. Generators that walk every y of a column pay it per
// column instead of per block; density_from_column finishes the job.
fn fill_density_column(mut column []f64, grid []f64, local_x int, local_z int) {
	mut gx := local_x / density_cell_xz
	mut gz := local_z / density_cell_xz
	if gx >= density_grid_xz - 1 {
		gx = density_grid_xz - 2
	}
	if gz >= density_grid_xz - 1 {
		gz = density_grid_xz - 2
	}
	fx := f64(local_x - gx * density_cell_xz) / f64(density_cell_xz)
	fz := f64(local_z - gz * density_cell_xz) / f64(density_cell_xz)
	for gy in 0 .. density_grid_y {
		c00 := grid[density_grid_index(gx, gy, gz)]
		c10 := grid[density_grid_index(gx + 1, gy, gz)]
		c01 := grid[density_grid_index(gx, gy, gz + 1)]
		c11 := grid[density_grid_index(gx + 1, gy, gz + 1)]
		x0 := lerp_f64(c00, c10, fx)
		x1 := lerp_f64(c01, c11, fx)
		column[gy] = lerp_f64(x0, x1, fz)
	}
}

fn density_from_column(column []f64, y int) f64 {
	mut gy := y / density_cell_y
	if gy >= density_grid_y - 1 {
		gy = density_grid_y - 2
	}
	fy := f64(y - gy * density_cell_y) / f64(density_cell_y)
	return lerp_f64(column[gy], column[gy + 1], fy)
}

fn density_from_grid(grid []f64, local_x int, y int, local_z int) f64 {
	mut gx := local_x / density_cell_xz
	mut gy := y / density_cell_y
	mut gz := local_z / density_cell_xz
	if gx >= density_grid_xz - 1 {
		gx = density_grid_xz - 2
	}
	if gy >= density_grid_y - 1 {
		gy = density_grid_y - 2
	}
	if gz >= density_grid_xz - 1 {
		gz = density_grid_xz - 2
	}
	fx := f64(local_x - gx * density_cell_xz) / f64(density_cell_xz)
	fy := f64(y - gy * density_cell_y) / f64(density_cell_y)
	fz := f64(local_z - gz * density_cell_xz) / f64(density_cell_xz)
	c000 := grid[density_grid_index(gx, gy, gz)]
	c100 := grid[density_grid_index(gx + 1, gy, gz)]
	c010 := grid[density_grid_index(gx, gy + 1, gz)]
	c110 := grid[density_grid_index(gx + 1, gy + 1, gz)]
	c001 := grid[density_grid_index(gx, gy, gz + 1)]
	c101 := grid[density_grid_index(gx + 1, gy, gz + 1)]
	c011 := grid[density_grid_index(gx, gy + 1, gz + 1)]
	c111 := grid[density_grid_index(gx + 1, gy + 1, gz + 1)]
	x00 := lerp_f64(c000, c100, fx)
	x10 := lerp_f64(c010, c110, fx)
	x01 := lerp_f64(c001, c101, fx)
	x11 := lerp_f64(c011, c111, fx)
	y0 := lerp_f64(x00, x10, fy)
	y1 := lerp_f64(x01, x11, fy)
	return lerp_f64(y0, y1, fz)
}

fn (g NetherGenerator) raw_block_at_density(x int, y int, z int, density f64) int {
	if y < g.dim.min_y || y > g.dim.max_y() {
		return air.network_id
	}
	if g.floor_bedrock_at(x, y, z) || g.roof_bedrock_at(x, y, z) {
		return bedrock.network_id
	}
	if y == g.dim.max_y() - 1 {
		return netherrack.network_id
	}
	if density > 0.0 {
		return netherrack.network_id
	}
	if y <= nether_lava_level {
		return lava.network_id
	}
	return air.network_id
}

fn (g NetherGenerator) raw_block_at(x int, y int, z int) int {
	return g.raw_block_at_density(x, y, z, g.density_at(x, y, z))
}

fn (g NetherGenerator) surface_patch_at(x int, y int, z int) int {
	n := hash3_unit(x / 2, y / 2, z / 2, nether_surface_salt)
	if y >= nether_lava_level - 1 && y <= nether_lava_level + 4 && n > 0.62 {
		return soul_sand.network_id
	}
	if n < 0.12 {
		return gravel.network_id
	}
	if y <= nether_lava_level + 2 && n > 0.82 {
		return magma_block.network_id
	}
	return netherrack.network_id
}

fn (g NetherGenerator) glowstone_at(x int, y int, z int) bool {
	raw := g.raw_block_at(x, y, z)
	above := g.raw_block_at(x, y + 1, z)
	return g.glowstone_at_raw(x, y, z, raw, above)
}

fn (g NetherGenerator) glowstone_at_raw(x int, y int, z int, raw int, above int) bool {
	if y <= nether_lava_level + 8 || y >= g.dim.max_y() - 2 || raw != air.network_id
		|| above == air.network_id {
		return false
	}
	return hash3_unit(x / 2, y / 2, z / 2, nether_glowstone_salt) > 0.965
}

fn (g NetherGenerator) decorate_nether_raw(x int, y int, z int, raw int, above int) int {
	if override := g.spawn_override(x, y, z) {
		return override
	}
	if raw == netherrack.network_id && y > g.dim.min_y + 4 && y < g.dim.max_y() - 1
		&& above == air.network_id {
		return g.surface_patch_at(x, y, z)
	}
	if g.glowstone_at_raw(x, y, z, raw, above) {
		return glowstone.network_id
	}
	return raw
}

fn (g NetherGenerator) nether_block_at_density(x int, y int, z int, density f64) int {
	raw := g.raw_block_at_density(x, y, z, density)
	above := g.raw_block_at(x, y + 1, z)
	return g.decorate_nether_raw(x, y, z, raw, above)
}

fn (g NetherGenerator) nether_block_at(x int, y int, z int) int {
	return g.nether_block_at_density(x, y, z, g.density_at(x, y, z))
}

fn (g NetherGenerator) nether_block_from_grid(grid []f64, x int, y int, z int, local_x int, local_z int) int {
	raw := g.raw_block_at_density(x, y, z, density_from_grid(grid, local_x, y, local_z))
	above := g.raw_block_at_density(x, y + 1, z, density_from_grid(grid, local_x, y + 1, local_z))
	return g.decorate_nether_raw(x, y, z, raw, above)
}

pub fn (g NetherGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	base_x := chunk_x * 16
	base_z := chunk_z * 16
	grid := g.density_grid(base_x, base_z)
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			world_x := base_x + x
			world_z := base_z + z
			c.set_biome(x, z, biome_hell)
			for y in g.dim.min_y .. g.dim.max_y() + 1 {
				block_id := g.nether_block_from_grid(grid, world_x, y, world_z, x, z)
				if block_id != air.network_id {
					c.set_block(x, y, z, block_from_id(block_id))
				}
			}
		}
	}
	return c
}

pub fn (g NetherGenerator) block_at(x int, y int, z int) int {
	return g.nether_block_at(x, y, z)
}

pub fn (g NetherGenerator) biome_at(x int, z int) int {
	return biome_hell
}

// End
const end_platform_size = 5
const end_island_radius = 96.0
const end_edge_jitter = 10.0
const end_hill_amplitude = 8.0
const end_island_salt = u32(601)
const end_hill_salt = u32(619)

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

fn (g EndGenerator) island_top_y(x int, z int) ?int {
	dist := dist2d(x, z)
	edge_noise := (fbm2d(f64(x) / 40.0, f64(z) / 40.0, end_island_salt, 3) - 0.5) * 2.0 * end_edge_jitter
	effective_radius := end_island_radius + edge_noise
	if dist > effective_radius {
		return none
	}
	floor_top := g.dim.min_y + g.layers().len - 1
	mut falloff := 1.0 - dist / effective_radius
	if falloff < 0 {
		falloff = 0
	}
	hill_noise := fbm2d(f64(x) / 30.0, f64(z) / 30.0, end_hill_salt, 3)
	extra := int(hill_noise * end_hill_amplitude * falloff)
	return floor_top + extra
}

pub fn (g EndGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	base_x := chunk_x * 16
	base_z := chunk_z * 16
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			world_x := base_x + x
			world_z := base_z + z
			c.set_biome(x, z, biome_the_end)
			top := g.island_top_y(world_x, world_z) or { continue }
			c.set_block(x, g.dim.min_y, z, bedrock)
			for y := g.dim.min_y + 1; y <= top; y++ {
				c.set_block(x, y, z, end_stone)
			}
		}
	}
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
	if y == g.dim.min_y {
		if _ := g.island_top_y(x, z) {
			return bedrock.network_id
		}
		return air.network_id
	}
	top := g.island_top_y(x, z) or { return air.network_id }
	if y > g.dim.min_y && y <= top {
		return end_stone.network_id
	}
	return air.network_id
}

pub fn (g EndGenerator) biome_at(x int, z int) int {
	return biome_the_end
}

pub fn new_generator(name string) Generator {
	mut g := Generator(FlatGenerator{})
	match name.to_lower() {
		'void' { g = VoidGenerator{} }
		'normal' { g = NormalGenerator{} }
		'nether' { g = NetherGenerator{} }
		'end' { g = EndGenerator{} }
		else {}
	}

	return g
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

// create resolves name to a Generator sized for dim. An empty name or the
// literal name "default" both mean "whatever this dimension's own default
// generator is" (dim.default_generator - 'normal' for overworld, 'nether' for
// nether, 'end' for end), so callers (e.g. /world create ... default) don't
// need to know each dimension's concrete generator name.
pub fn (r &GeneratorRegistry) create(name string, dim Dimension) ?Generator {
	lower := name.to_lower().trim_space()
	resolved := if lower == '' || lower == 'default' { dim.default_generator } else { lower }
	factory := r.factories[resolved.to_lower()] or { return none }
	return factory(dim)
}

pub fn (r &GeneratorRegistry) names() []string {
	mut out := []string{cap: r.factories.len}
	for name, _ in r.factories {
		out << name
	}
	return out
}
