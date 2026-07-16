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

pub fn (g VoidGenerator) biome_at(x int, z int) int {
	return default_biome_for(g.dim)
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
	return safe_spawn_y(g, g.dim, 0, 0, g.dim.min_y + g.layers().len)
}

pub fn (g FlatGenerator) uses_blocks() bool {
	return true
}

pub fn (g FlatGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	fill_flat_layers(mut c, g.dim.min_y, g.layers())
	biome := default_biome_for(g.dim)
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			c.set_biome(x, z, biome)
		}
	}
	return c
}

pub fn (g FlatGenerator) block_at(x int, y int, z int) int {
	return flat_layer_at(y, g.dim.min_y, g.layers())
}

pub fn (g FlatGenerator) biome_at(x int, z int) int {
	return default_biome_for(g.dim)
}

// ---- Nether ----
//
// PNX/vanilla-inspired but intentionally smaller: bedrock shell, a lava sea,
// rough lower/upper netherrack masses and a wide traversable middle cavern.
// Explicitly out of scope: extra nether biomes, structures, netherite and portals.
pub const nether_lava_level = 31
const nether_spawn_floor_y = 63
const nether_floor_salt = u32(401)
const nether_ceiling_salt = u32(409)
const nether_density_salt = u32(419)
const nether_detail_salt = u32(421)
const nether_surface_salt = u32(431)
const nether_glowstone_salt = u32(457)
const nether_density_cell_xz = 4
const nether_density_cell_y = 8
const nether_density_grid_xz = 5
const nether_density_grid_y = 17

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
	return (gx * nether_density_grid_y + gy) * nether_density_grid_xz + gz
}

fn (g NetherGenerator) density_at(x int, y int, z int) f64 {
	main := (fbm3d(f64(x) / 38.0, f64(y) / 28.0, f64(z) / 38.0, nether_density_salt, 4) - 0.5) * 2.0
	detail := (fbm3d(f64(x) / 16.0, f64(y) / 14.0, f64(z) / 16.0, nether_detail_salt, 2) - 0.5) * 0.65
	lower := f64_clamp((38.0 - f64(y)) / 28.0, 0.0, 1.0) * 1.35
	upper := f64_clamp((f64(y) - 82.0) / 32.0, 0.0, 1.0) * 1.35
	middle_open := 0.22 + f64_clamp((f64(y) - 38.0) / 26.0, 0.0, 1.0) * 0.10
	return main + detail + lower + upper - middle_open
}

fn (g NetherGenerator) density_grid(base_x int, base_z int) []f64 {
	mut grid := []f64{len: nether_density_grid_xz * nether_density_grid_y * nether_density_grid_xz}
	for gx in 0 .. nether_density_grid_xz {
		world_x := base_x + gx * nether_density_cell_xz
		for gy in 0 .. nether_density_grid_y {
			y := gy * nether_density_cell_y
			for gz in 0 .. nether_density_grid_xz {
				world_z := base_z + gz * nether_density_cell_xz
				grid[density_grid_index(gx, gy, gz)] = g.density_at(world_x, y, world_z)
			}
		}
	}
	return grid
}

fn density_from_grid(grid []f64, local_x int, y int, local_z int) f64 {
	mut gx := local_x / nether_density_cell_xz
	mut gy := y / nether_density_cell_y
	mut gz := local_z / nether_density_cell_xz
	if gx >= nether_density_grid_xz - 1 {
		gx = nether_density_grid_xz - 2
	}
	if gy >= nether_density_grid_y - 1 {
		gy = nether_density_grid_y - 2
	}
	if gz >= nether_density_grid_xz - 1 {
		gz = nether_density_grid_xz - 2
	}
	fx := f64(local_x - gx * nether_density_cell_xz) / f64(nether_density_cell_xz)
	fy := f64(y - gy * nether_density_cell_y) / f64(nether_density_cell_y)
	fz := f64(local_z - gz * nether_density_cell_xz) / f64(nether_density_cell_xz)
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

// Overworld default survival generator
const sea_level = 62
const ocean_threshold = 0.42
const desert_temp_min = 0.55
const desert_moisture_max = 0.45
const snowy_temp_max = 0.45
const taiga_temp_max = 0.60
const taiga_moisture_min = 0.50
const dirt_depth = 3
const desert_sand_depth = 4
const desert_sandstone_depth = 3
const tree_trunk_height = 5
const tree_root_margin = 1

const terrain_salt = u32(11)
const temperature_salt = u32(23)
const moisture_salt = u32(29)
const ocean_salt = u32(41)
const tree_salt = u32(53)

struct OreVein {
	block  Block
	min_y  int
	max_y  int
	chance f64
	salt   u32
}

fn ore_veins() []OreVein {
	return [
		OreVein{coal_ore, 0, 128, 0.010, 101},
		OreVein{iron_ore, 0, 64, 0.010, 103},
		OreVein{redstone_ore, 0, 16, 0.014, 109},
		OreVein{gold_ore, 0, 32, 0.002, 107},
		OreVein{lapis_ore, 0, 32, 0.0007, 113},
		OreVein{diamond_ore, 0, 16, 0.0017, 127},
	]
}

fn ore_at(x int, y int, z int) ?Block {
	for vein in ore_veins() {
		if y < vein.min_y || y >= vein.max_y {
			continue
		}
		if hash3_unit(x, y, z, vein.salt) < vein.chance {
			return vein.block
		}
	}
	return none
}

pub struct NormalGenerator {
	dim Dimension = overworld
}

pub fn (g NormalGenerator) uses_blocks() bool {
	return true
}

pub fn (g NormalGenerator) biome_at(x int, z int) int {
	ocean_n := fbm2d(f64(x) / 200.0, f64(z) / 200.0, ocean_salt, 3)
	if ocean_n < ocean_threshold {
		return biome_ocean
	}
	temp := fbm2d(f64(x) / 300.0, f64(z) / 300.0, temperature_salt, 3)
	moisture := fbm2d(f64(x) / 300.0, f64(z) / 300.0, moisture_salt, 3)
	if temp > desert_temp_min && moisture < desert_moisture_max {
		return biome_desert
	}
	if temp < snowy_temp_max && moisture > taiga_moisture_min {
		return biome_snowy_taiga
	}
	if temp < taiga_temp_max && moisture > taiga_moisture_min {
		return biome_taiga
	}
	return plains_biome_id
}

fn (g NormalGenerator) height_params(biome int) (int, f64) {
	return match biome {
		biome_desert { 64, 3.0 }
		biome_taiga { 68, 9.0 }
		biome_snowy_taiga { 70, 11.0 }
		biome_ocean { 50, 5.0 }
		else { 64, 5.0 }
	}
}

fn (g NormalGenerator) surface_height(x int, z int, biome int) int {
	base, amplitude := g.height_params(biome)
	n := fbm2d(f64(x) / 90.0, f64(z) / 90.0, terrain_salt, 4)
	return base + int((n - 0.5) * 2.0 * amplitude)
}

fn column_top_for(biome int, height int) int {
	return match biome {
		biome_snowy_taiga { height + 1 }
		biome_ocean { sea_level }
		else { height }
	}
}

fn (g NormalGenerator) stone_or_ore(x int, y int, z int) int {
	if ore := ore_at(x, y, z) {
		return ore.network_id
	}
	return stone.network_id
}

fn (g NormalGenerator) ocean_block(y int, height int) int {
	if y > height {
		return water.network_id
	}
	if y == height {
		return sand.network_id
	}
	return stone.network_id
}

fn (g NormalGenerator) desert_block(x int, y int, z int, height int) int {
	if y > height - desert_sand_depth {
		return sand.network_id
	}
	if y > height - desert_sand_depth - desert_sandstone_depth {
		return sandstone.network_id
	}
	return g.stone_or_ore(x, y, z)
}

fn (g NormalGenerator) land_block(biome int, x int, y int, z int, height int) int {
	if biome == biome_snowy_taiga && y == height + 1 {
		return snow.network_id
	}
	if y == height {
		return grass_block.network_id
	}
	if y > height - dirt_depth {
		return dirt.network_id
	}
	return g.stone_or_ore(x, y, z)
}

fn (g NormalGenerator) terrain_block(biome int, height int, x int, y int, z int) int {
	return match biome {
		biome_ocean { g.ocean_block(y, height) }
		biome_desert { g.desert_block(x, y, z, height) }
		else { g.land_block(biome, x, y, z, height) }
	}
}

fn tree_root_here(x int, z int, biome int) bool {
	if biome != plains_biome_id && biome != biome_taiga && biome != biome_snowy_taiga {
		return false
	}
	local_x := ((x % 16) + 16) % 16
	local_z := ((z % 16) + 16) % 16
	if local_x < tree_root_margin || local_x >= 16 - tree_root_margin || local_z < tree_root_margin
		|| local_z >= 16 - tree_root_margin {
		return false
	}
	chance := if biome == biome_taiga || biome == biome_snowy_taiga { 0.02 } else { 0.006 }
	return hash3_unit(x, 0, z, tree_salt) < chance
}

fn tree_shape_block(dx int, dz int, y_rel int, log_id int, leaves_id int) ?int {
	if y_rel < 0 || y_rel > tree_trunk_height {
		return none
	}
	if dx == 0 && dz == 0 {
		if y_rel < tree_trunk_height {
			return log_id
		}
		return leaves_id
	}
	if y_rel == tree_trunk_height {
		return none
	}
	if y_rel >= tree_trunk_height - 3 && dx >= -1 && dx <= 1 && dz >= -1 && dz <= 1 {
		return leaves_id
	}
	return none
}

fn tree_blocks_for(biome int) (int, int) {
	if biome == biome_taiga || biome == biome_snowy_taiga {
		return spruce_log.network_id, spruce_leaves.network_id
	}
	return oak_log.network_id, oak_leaves.network_id
}

fn (g NormalGenerator) tree_override(x int, y int, z int) ?int {
	for rx := x - 1; rx <= x + 1; rx++ {
		for rz := z - 1; rz <= z + 1; rz++ {
			root_biome := g.biome_at(rx, rz)
			if !tree_root_here(rx, rz, root_biome) {
				continue
			}
			root_height := g.surface_height(rx, rz, root_biome)
			base_y := root_height + 1
			log_id, leaves_id := tree_blocks_for(root_biome)
			if block_id := tree_shape_block(x - rx, z - rz, y - base_y, log_id, leaves_id) {
				return block_id
			}
		}
	}
	return none
}

fn (g NormalGenerator) column_block(x int, y int, z int) int {
	biome := g.biome_at(x, z)
	height := g.surface_height(x, z, biome)
	top := column_top_for(biome, height)
	if y > top {
		return air.network_id
	}
	return g.terrain_block(biome, height, x, y, z)
}

pub fn (g NormalGenerator) block_at(x int, y int, z int) int {
	if y < g.dim.min_y || y > g.dim.max_y() {
		return air.network_id
	}
	if block_id := g.tree_override(x, y, z) {
		return block_id
	}
	return g.column_block(x, y, z)
}

pub fn (g NormalGenerator) spawn_y() int {
	biome := g.biome_at(0, 0)
	return safe_spawn_y(g, g.dim, 0, 0, column_top_for(biome, g.surface_height(0, 0, biome)) + 1)
}

pub fn (g NormalGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	mut heights := []int{len: 256}
	mut biomes := []int{len: 256}
	base_x := chunk_x * 16
	base_z := chunk_z * 16

	for x in 0 .. 16 {
		for z in 0 .. 16 {
			world_x := base_x + x
			world_z := base_z + z
			biome := g.biome_at(world_x, world_z)
			biomes[x * 16 + z] = biome
			c.set_biome(x, z, biome)
			height := g.surface_height(world_x, world_z, biome)
			heights[x * 16 + z] = height
			top := column_top_for(biome, height)
			for y := g.dim.min_y; y <= top; y++ {
				block_id := g.terrain_block(biome, height, world_x, y, world_z)
				if block_id != air.network_id {
					c.set_block(x, y, z, block_from_id(block_id))
				}
			}
		}
	}

	for x in 0 .. 16 {
		for z in 0 .. 16 {
			biome := biomes[x * 16 + z]
			world_x := base_x + x
			world_z := base_z + z
			if !tree_root_here(world_x, world_z, biome) {
				continue
			}
			base_y := heights[x * 16 + z] + 1
			log_id, leaves_id := tree_blocks_for(biome)
			for dx in -1 .. 2 {
				for dz in -1 .. 2 {
					lx := x + dx
					lz := z + dz
					if lx < 0 || lx >= 16 || lz < 0 || lz >= 16 {
						continue
					}
					for y_rel in 0 .. tree_trunk_height + 1 {
						if block_id := tree_shape_block(dx, dz, y_rel, log_id, leaves_id) {
							c.set_block(lx, base_y + y_rel, lz, block_from_id(block_id))
						}
					}
				}
			}
		}
	}

	return c
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
