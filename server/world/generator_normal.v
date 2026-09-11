module world

import math

// The overworld generator shapes terrain from a single 3D noise field that is
// biased towards solid ground by a per column elevation band. The band comes
// from the biome map and is gaussian blurred across neighbouring columns so
// biome borders slope instead of forming cliffs.
const normal_water_height = 62
const normal_terrain_height = 128
const normal_smooth_size = 2
const normal_padded_size = 16 + normal_smooth_size * 2
const normal_biome_buckets = 64

// Octave amplitudes sum to 1 + p + p^2 + p^3 for the four terrain octaves. The
// noise helpers normalise to [0, 1), so undo that to keep the raw range the
// elevation bias was tuned against.
const normal_terrain_persistence = 0.25
const normal_terrain_amplitude = 1.328125
const normal_terrain_scale = 32.0
const normal_climate_scale = 512.0
const normal_climate_persistence = 0.0625

const normal_terrain_salt = u64(3)
const normal_temperature_salt = u64(5)
const normal_rainfall_salt = u64(7)

// cave carving — two overlapping noise fields ("spaghetti") plus a separate
// wider field ("cheese") cut open cavities of different shapes.
const normal_cave_spaghetti_salt_a = u64(11)
const normal_cave_spaghetti_salt_b = u64(13)
const normal_cave_cheese_salt = u64(17)
const normal_cave_scale = 48.0
const normal_cave_cheese_scale = 64.0
const normal_cave_spaghetti_threshold = 0.03
const normal_cave_cheese_threshold = 0.72
const normal_cave_lava_level = 10

struct OreType {
	material      Block
	cluster_count int
	cluster_size  int
	min_height    int
	max_height    int
}

struct TreeSpec {
	base_amount int
	log         Block
	leaves      Block
	conifer     bool
}

pub struct NormalGenerator {
	dim  Dimension = overworld
	seed i64
}

pub fn (g NormalGenerator) uses_blocks() bool {
	return true
}

// ---- biome map ----

fn normal_climate(x int, z int, salt u64) f64 {
	return fbm2d_persist(f64(x) / normal_climate_scale, f64(z) / normal_climate_scale, salt, 2,
		normal_climate_persistence)
}

fn normal_biome_lookup(temperature f64, rainfall f64) int {
	if rainfall < 0.25 {
		if temperature < 0.7 {
			return biome_ocean
		}
		if temperature < 0.85 {
			return biome_river
		}
		return biome_swampland
	}
	if rainfall < 0.60 {
		if temperature < 0.25 {
			return biome_ice_plains
		}
		if temperature < 0.75 {
			return plains_biome_id
		}
		return biome_desert
	}
	if rainfall < 0.80 {
		if temperature < 0.25 {
			return biome_taiga
		}
		if temperature < 0.75 {
			return biome_forest
		}
		return biome_birch_forest
	}
	if temperature < 0.20 {
		return biome_extreme_hills
	}
	if temperature < 0.40 {
		return biome_extreme_hills_edge
	}
	return biome_river
}

// select_biome quantises the climate noise into a fixed lookup grid so the
// biome map has flat plateaus rather than a different result for every block.
fn normal_select_biome(x int, z int, mask u64) int {
	temperature := int(normal_climate(x, z, normal_temperature_salt ^ mask) * f64(normal_biome_buckets - 1))
	rainfall := int(normal_climate(x, z, normal_rainfall_salt ^ mask) * f64(normal_biome_buckets - 1))
	return normal_biome_lookup(f64(temperature) / f64(normal_biome_buckets - 1),
		f64(rainfall) / f64(normal_biome_buckets - 1))
}

// normal_biome_jitter breaks up the straight edges the quantised biome map
// would otherwise produce by nudging the sample point by up to one block.
fn normal_biome_jitter(x int, z int, mask u64) (int, int) {
	mut hash := i64(x) * 2345803 ^ i64(z) * 9236449 ^ i64(mask)
	hash *= hash + 223
	mut x_noise := int((hash >> 20) & 3)
	mut z_noise := int((hash >> 22) & 3)
	if x_noise == 3 {
		x_noise = 1
	}
	if z_noise == 3 {
		z_noise = 1
	}
	return x_noise - 1, z_noise - 1
}

pub fn (g NormalGenerator) biome_at(x int, z int) int {
	mask := seed_mask(g.seed)
	dx, dz := normal_biome_jitter(x, z, mask)
	return normal_select_biome(x + dx, z + dz, mask)
}

fn normal_elevation(biome int) (int, int) {
	return match biome {
		biome_ocean { 46, 58 }
		biome_desert { 63, 74 }
		biome_extreme_hills { 63, 127 }
		biome_extreme_hills_edge { 63, 97 }
		biome_forest, biome_birch_forest, biome_taiga { 63, 81 }
		biome_swampland { 62, 63 }
		biome_river { 58, 62 }
		biome_ice_plains { 63, 74 }
		else { 63, 68 }
	}
}

fn normal_ground_cover(biome int) []Block {
	return match biome {
		biome_ocean { [gravel, gravel, gravel, gravel, gravel] }
		biome_desert { [sand, sand, sandstone, sandstone, sandstone] }
		biome_river { [dirt, dirt, dirt, dirt, dirt] }
		biome_taiga, biome_ice_plains { [snow, grass_block, dirt, dirt, dirt] }
		else { [grass_block, dirt, dirt, dirt, dirt] }
	}
}

fn normal_tree_spec(biome int) ?TreeSpec {
	return match biome {
		biome_taiga { TreeSpec{10, spruce_log, spruce_leaves, true} }
		biome_forest, biome_birch_forest { TreeSpec{5, oak_log, oak_leaves, false} }
		biome_extreme_hills, biome_extreme_hills_edge { TreeSpec{1, oak_log, oak_leaves, false} }
		else { none }
	}
}

fn normal_ore_types() []OreType {
	return [
		OreType{coal_ore, 20, 16, 0, 128},
		OreType{iron_ore, 20, 8, 0, 64},
		OreType{redstone_ore, 8, 7, 0, 16},
		OreType{lapis_ore, 1, 6, 0, 32},
		OreType{gold_ore, 2, 8, 0, 32},
		OreType{diamond_ore, 1, 7, 0, 16},
		OreType{dirt, 20, 32, 0, 128},
		OreType{gravel, 10, 16, 0, 128},
	]
}

fn normal_biome_ore_types(biome int) []OreType {
	if biome == biome_extreme_hills || biome == biome_extreme_hills_edge {
		return [OreType{emerald_ore, 11, 1, 0, 32}]
	}
	return []
}

// ---- elevation smoothing ----

// gaussian_kernel_1d is one axis of a separable bell shaped blur. Blurring the
// elevation band twice along a single axis costs 2n weights per column instead
// of the n^2 a square kernel would need.
fn gaussian_kernel_1d() []f64 {
	bell_size := 1.0 / f64(normal_smooth_size)
	bell_height := 2.0 * f64(normal_smooth_size)
	mut kernel := []f64{len: normal_smooth_size * 2 + 1}
	for i in 0 .. kernel.len {
		b := bell_size * f64(i - normal_smooth_size)
		kernel[i] = math.sqrt(bell_height) * math.exp(-(b * b) / 2.0)
	}
	return kernel
}

fn kernel_weight_sum(kernel []f64) f64 {
	mut sum := 0.0
	for w in kernel {
		sum += w
	}
	return sum
}

const normal_kernel = gaussian_kernel_1d()
const normal_kernel_weight_sum = kernel_weight_sum(normal_kernel)

// gaussian_smooth_elevation turns the padded biome map into per column min/max
// elevation bounds. biomes is indexed x * normal_padded_size + z with
// normal_smooth_size blocks of padding on every side.
fn gaussian_smooth_elevation(biomes []int) ([]f64, []f64) {
	kernel := normal_kernel
	weight_sum := normal_kernel_weight_sum

	mut min_x := []f64{len: 16 * normal_padded_size}
	mut max_x := []f64{len: 16 * normal_padded_size}
	for x in 0 .. 16 {
		for z in 0 .. normal_padded_size {
			mut min_sum := 0.0
			mut max_sum := 0.0
			for s in 0 .. kernel.len {
				biome := biomes[(x + s) * normal_padded_size + z]
				min_elevation, max_elevation := normal_elevation(biome)
				min_sum += f64(min_elevation - 1) * kernel[s]
				max_sum += f64(max_elevation) * kernel[s]
			}
			min_x[x * normal_padded_size + z] = min_sum / weight_sum
			max_x[x * normal_padded_size + z] = max_sum / weight_sum
		}
	}

	mut min_heights := []f64{len: 256}
	mut max_heights := []f64{len: 256}
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			mut min_sum := 0.0
			mut max_sum := 0.0
			for s in 0 .. kernel.len {
				min_sum += min_x[x * normal_padded_size + z + s] * kernel[s]
				max_sum += max_x[x * normal_padded_size + z + s] * kernel[s]
			}
			min_heights[x * 16 + z] = min_sum / weight_sum
			max_heights[x * 16 + z] = max_sum / weight_sum
		}
	}
	return min_heights, max_heights
}

// smoothed_elevation is gaussian_smooth_elevation for a single column, used by
// the block_at path where no chunk wide biome map is available.
fn (g NormalGenerator) smoothed_elevation(x int, z int) (f64, f64) {
	kernel := normal_kernel
	weight_sum := normal_kernel_weight_sum
	mut min_sum := 0.0
	mut max_sum := 0.0
	for sx in 0 .. kernel.len {
		for sz in 0 .. kernel.len {
			biome := g.biome_at(x + sx - normal_smooth_size, z + sz - normal_smooth_size)
			min_elevation, max_elevation := normal_elevation(biome)
			weight := kernel[sx] * kernel[sz]
			min_sum += f64(min_elevation - 1) * weight
			max_sum += f64(max_elevation) * weight
		}
	}
	total := weight_sum * weight_sum
	return min_sum / total, max_sum / total
}

// ---- terrain ----

fn (g NormalGenerator) terrain_noise(x int, y int, z int) f64 {
	n := fbm3d_persist(f64(x) / normal_terrain_scale, f64(y) / normal_terrain_scale,
		f64(z) / normal_terrain_scale, normal_terrain_salt ^ seed_mask(g.seed), 4, normal_terrain_persistence)
	return (n - 0.5) * 2.0 * normal_terrain_amplitude
}

// normal_terrain_id biases the noise field by how far y sits inside the
// column's elevation band: below the band everything is solid, above it
// nothing is, and the noise only decides the fuzzy middle.
fn normal_terrain_id(y int, min_sum f64, max_sum f64, noise f64) int {
	smooth_height := (max_sum - min_sum) / 2.0
	if smooth_height <= 0 {
		return air.network_id
	}
	value := noise - 1.0 / smooth_height * (f64(y) - smooth_height - min_sum)
	if value > 0 {
		return stone.network_id
	}
	if y <= normal_water_height {
		return water.network_id
	}
	return air.network_id
}

fn normal_column_top(max_sum f64) int {
	mut top := int(math.ceil(max_sum))
	if top < normal_water_height {
		top = normal_water_height
	}
	if top > normal_terrain_height - 1 {
		top = normal_terrain_height - 1
	}
	return top
}

fn ground_cover_solid(b Block) bool {
	return b.network_id != snow.network_id
}

// apply_ground_cover swaps the top few stone blocks of a column for the
// biome's surface material. A non solid first layer (snow) sits on top of the
// surface instead of replacing it, hence the one block offset.
fn apply_ground_cover(mut ids []int, limit int, cover []Block) {
	if cover.len == 0 || limit <= 0 {
		return
	}
	mut start := limit - 1
	for start > 0 && (ids[start] == air.network_id || ids[start] == water.network_id) {
		start--
	}
	if start <= 0 {
		return
	}
	if !ground_cover_solid(cover[0]) {
		start++
	}
	if start > limit - 1 {
		start = limit - 1
	}
	end := start - cover.len
	for y := start; y > end && y >= 0; y-- {
		b := cover[start - y]
		if ids[y] == air.network_id && ground_cover_solid(b) {
			break
		}
		if !ground_cover_solid(b) && ids[y] == water.network_id {
			continue
		}
		ids[y] = b.network_id
	}
}

// column_ids builds one full column, terrain plus ground cover. Populators are
// chunk scoped and deliberately left out so this stays a pure function of the
// column's coordinates.
fn (g NormalGenerator) column_ids(x int, z int) []int {
	min_sum, max_sum := g.smoothed_elevation(x, z)
	mut ids := []int{len: normal_terrain_height, init: air.network_id}
	ids[0] = bedrock.network_id
	for y := 1; y <= normal_column_top(max_sum); y++ {
		ids[y] = normal_terrain_id(y, min_sum, max_sum, g.terrain_noise(x, y, z))
	}
	apply_ground_cover(mut ids, ids.len, normal_ground_cover(g.biome_at(x, z)))
	// carve the same way generate() does so single block lookups stay consistent
	mask := seed_mask(g.seed)
	for y := 1; y < normal_terrain_height - 1; y++ {
		if ids[y] != stone.network_id && ids[y] != dirt.network_id && ids[y] != gravel.network_id {
			continue
		}
		sx := f64(x) / normal_cave_scale
		sy := f64(y) / normal_cave_scale
		sz := f64(z) / normal_cave_scale
		na := fbm3d(sx, sy, sz, normal_cave_spaghetti_salt_a ^ mask, 3) - 0.5
		nb := fbm3d(sx, sy, sz, normal_cave_spaghetti_salt_b ^ mask, 3) - 0.5
		spaghetti := na * na + nb * nb < normal_cave_spaghetti_threshold
		cx := f64(x) / normal_cave_cheese_scale
		cy := f64(y) / normal_cave_cheese_scale
		cz := f64(z) / normal_cave_cheese_scale
		cheese := fbm3d(cx, cy, cz, normal_cave_cheese_salt ^ mask, 2) > normal_cave_cheese_threshold
		if !spaghetti && !cheese {
			continue
		}
		if y + 1 < normal_terrain_height && (ids[y + 1] == air.network_id || ids[y + 1] == water.network_id) {
			if y > normal_water_height {
				continue
			}
		}
		if y <= normal_cave_lava_level {
			ids[y] = lava.network_id
		} else if y <= normal_water_height && y + 1 < normal_terrain_height
			&& ids[y + 1] == water.network_id {
			ids[y] = water.network_id
		} else {
			ids[y] = air.network_id
		}
	}
	return ids
}

pub fn (g NormalGenerator) block_at(x int, y int, z int) int {
	if y < 0 || y >= normal_terrain_height || y < g.dim.min_y || y > g.dim.max_y() {
		return air.network_id
	}
	return g.column_ids(x, z)[y]
}

// A world from before seeds spawns where it always has, over the origin. A
// seeded one can have ocean there, so it looks outward ring by ring for the
// nearest dry land, as far as the rings reach.
const normal_spawn_search_step = 16
const normal_spawn_search_rings = 64

pub fn (g NormalGenerator) spawn_point() SpawnPoint {
	if g.seed != 0 {
		for ring in 0 .. normal_spawn_search_rings + 1 {
			for pos in spawn_ring(ring) {
				x := pos[0] * normal_spawn_search_step
				z := pos[1] * normal_spawn_search_step
				if y := g.dry_land_y(x, z) {
					return SpawnPoint{
						x: x
						y: y
						z: z
					}
				}
			}
		}
	}
	return SpawnPoint{
		y: safe_spawn_y(g, g.dim, 0, 0, column_top(g.column_ids(0, 0)) + 1)
	}
}

// dry_land_y is the height a player stands at on column x, z or none when
// the column is under water. The biome is asked first: it is far cheaper than
// building the column and rules out oceans and rivers on its own.
fn (g NormalGenerator) dry_land_y(x int, z int) ?int {
	biome := g.biome_at(x, z)
	if biome == biome_ocean || biome == biome_river {
		return none
	}
	ids := g.column_ids(x, z)
	top := column_top(ids)
	if top <= 0 || !spawn_floor_solid(ids[top]) {
		return none
	}
	return top + 1
}

// column_top is the highest block of a column that isn't air.
fn column_top(ids []int) int {
	mut top := ids.len - 1
	for top > 0 && ids[top] == air.network_id {
		top--
	}
	return top
}

// spawn_ring lists the positions on the square ring ring steps out from the
// origin.
fn spawn_ring(ring int) [][]int {
	if ring == 0 {
		return [[0, 0]]
	}
	mut out := [][]int{cap: ring * 8}
	for d in -ring .. ring + 1 {
		out << [d, -ring]
		out << [d, ring]
	}
	for d in -ring + 1 .. ring {
		out << [-ring, d]
		out << [ring, d]
	}
	return out
}

pub fn (g NormalGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	base_x := chunk_x * 16
	base_z := chunk_z * 16

	mut biomes := []int{len: normal_padded_size * normal_padded_size}
	for x in 0 .. normal_padded_size {
		for z in 0 .. normal_padded_size {
			biomes[x * normal_padded_size + z] = g.biome_at(base_x + x - normal_smooth_size,

				base_z + z - normal_smooth_size)
		}
	}
	min_heights, max_heights := gaussian_smooth_elevation(biomes)
	grid := build_density_grid(base_x, base_z, fn [g] (x int, y int, z int) f64 {
		return g.terrain_noise(x, y, z)
	})

	mut ids := []int{len: normal_terrain_height}
	mut column := []f64{len: density_grid_y}
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			biome := biomes[(x + normal_smooth_size) * normal_padded_size + z + normal_smooth_size]
			c.set_biome(x, z, biome)

			min_sum := min_heights[x * 16 + z]
			max_sum := max_heights[x * 16 + z]
			top := normal_column_top(max_sum)
			// Everything above top is air, so only the part of the column that
			// gets written is worth clearing - the rest was 128 stores per
			// column that nothing ever read.
			mut span := top + 2
			if span > normal_terrain_height {
				span = normal_terrain_height
			}
			for y in 0 .. span {
				ids[y] = air.network_id
			}
			ids[0] = bedrock.network_id
			fill_density_column(mut column, grid, x, z)
			for y := 1; y <= top; y++ {
				ids[y] = normal_terrain_id(y, min_sum, max_sum, density_from_column(column, y))
			}
			apply_ground_cover(mut ids, span, normal_ground_cover(biome))
			c.set_column(x, z, 0, ids[..span])
		}
	}

	carve_caves(mut c, chunk_x, chunk_z, seed_mask(g.seed))
	g.populate(mut c, chunk_x, chunk_z)
	return c
}

// carve_caves punches holes through solid stone using two noise layers. The
// spaghetti pass intersects two thin bands to create winding tunnels; the
// cheese pass opens up wide chambers where the noise is high enough. Blocks
// below the lava level get filled with lava, blocks between the lava level
// and the water height get filled with water when adjacent to water above.
fn carve_caves(mut c Chunk, chunk_x int, chunk_z int, mask u64) {
	base_x := chunk_x * 16
	base_z := chunk_z * 16
	for x in 0 .. 16 {
		wx := base_x + x
		for z in 0 .. 16 {
			wz := base_z + z
			for y := 1; y < normal_terrain_height - 1; y++ {
				id := c.block_id(x, y, z)
				if id != stone.network_id && id != dirt.network_id && id != gravel.network_id {
					continue
				}
				sx := f64(wx) / normal_cave_scale
				sy := f64(y) / normal_cave_scale
				sz := f64(wz) / normal_cave_scale

				na := fbm3d(sx, sy, sz, normal_cave_spaghetti_salt_a ^ mask, 3) - 0.5
				nb := fbm3d(sx, sy, sz, normal_cave_spaghetti_salt_b ^ mask, 3) - 0.5
				spaghetti := na * na + nb * nb < normal_cave_spaghetti_threshold

				cx := f64(wx) / normal_cave_cheese_scale
				cy := f64(y) / normal_cave_cheese_scale
				cz := f64(wz) / normal_cave_cheese_scale
				cheese := fbm3d(cx, cy, cz, normal_cave_cheese_salt ^ mask, 2) > normal_cave_cheese_threshold

				if !spaghetti && !cheese {
					continue
				}
				// don't carve through the surface — keep solid ground above
				if y + 1 < normal_terrain_height {
					above := c.block_id(x, y + 1, z)
					if above == air.network_id || above == water.network_id {
						if y > normal_water_height {
							continue
						}
					}
				}
				if y <= normal_cave_lava_level {
					c.set_block(x, y, z, lava)
				} else if y <= normal_water_height && y + 1 < normal_terrain_height
					&& c.block_id(x, y + 1, z) == water.network_id {
					c.set_block(x, y, z, water)
				} else {
					c.set_block(x, y, z, air)
				}
			}
		}
	}
}

// ---- populators ----

fn (g NormalGenerator) populate(mut c Chunk, chunk_x int, chunk_z int) {
	mut r := new_random_wide(u64(u32(0xdeadbeef) ^ (u32(chunk_x) << 8) ^ u32(chunk_z)) ^ seed_mask(g.seed))
	biome := c.biome_id(7, 7)

	for t in normal_ore_types() {
		populate_ore(mut c, t, mut r)
	}
	for t in normal_biome_ore_types(biome) {
		populate_ore(mut c, t, mut r)
	}
	if spec := normal_tree_spec(biome) {
		populate_trees(mut c, spec, mut r)
	}
}

fn populate_ore(mut c Chunk, t OreType, mut r Random) {
	for _ in 0 .. t.cluster_count {
		x := r.next_range(0, 15)
		y := r.next_range(t.min_height, t.max_height)
		z := r.next_range(0, 15)
		if y >= normal_terrain_height || c.block_id(x, y, z) != stone.network_id {
			continue
		}
		place_ore_cluster(mut c, t, x, y, z, mut r)
	}
}

// place_ore_cluster sweeps a shrinking sphere along a randomly angled line,
// which gives the elongated blobs ore veins are made of.
fn place_ore_cluster(mut c Chunk, t OreType, x int, y int, z int, mut r Random) {
	size := f64(t.cluster_size)
	angle := r.next_float() * math.pi
	offset_x := math.cos(angle) * size / 8.0
	offset_z := math.sin(angle) * size / 8.0
	x1 := f64(x) + offset_x
	x2 := f64(x) - offset_x
	z1 := f64(z) + offset_z
	z2 := f64(z) - offset_z
	y1 := f64(y + r.next_bounded_int(3) + 2)
	y2 := f64(y + r.next_bounded_int(3) + 2)

	for count := 0; count <= t.cluster_size; count++ {
		progress := f64(count) / size
		center_x := x1 + (x2 - x1) * progress
		center_y := y1 + (y2 - y1) * progress
		center_z := z1 + (z2 - z1) * progress
		radius := ((math.sin(f64(count) * (math.pi / size)) + 1) * r.next_float() * size / 16.0 + 1) / 2.0
		place_ore_sphere(mut c, t.material, center_x, center_y, center_z, radius)
	}
}

fn place_ore_sphere(mut c Chunk, material Block, center_x f64, center_y f64, center_z f64, radius f64) {
	if radius <= 0 {
		return
	}
	for xx := int(center_x - radius); xx <= int(center_x + radius); xx++ {
		if xx < 0 || xx > 15 {
			continue
		}
		mut size_x := (f64(xx) + 0.5 - center_x) / radius
		size_x *= size_x
		if size_x >= 1 {
			continue
		}
		for yy := int(center_y - radius); yy <= int(center_y + radius); yy++ {
			if yy <= 0 || yy >= normal_terrain_height {
				continue
			}
			mut size_y := (f64(yy) + 0.5 - center_y) / radius
			size_y *= size_y
			if size_x + size_y >= 1 {
				continue
			}
			for zz := int(center_z - radius); zz <= int(center_z + radius); zz++ {
				if zz < 0 || zz > 15 {
					continue
				}
				mut size_z := (f64(zz) + 0.5 - center_z) / radius
				size_z *= size_z
				if size_x + size_y + size_z >= 1 {
					continue
				}
				if c.block_id(xx, yy, zz) == stone.network_id {
					c.set_block(xx, yy, zz, material)
				}
			}
		}
	}
}

fn tree_can_override(id int) bool {
	return id == air.network_id || id == oak_leaves.network_id || id == spruce_leaves.network_id
		|| id == snow.network_id
}

fn tree_soil(id int) bool {
	return id == grass_block.network_id || id == dirt.network_id
}

fn chunk_id_or_air(c &Chunk, x int, y int, z int) int {
	if x < 0 || x > 15 || z < 0 || z > 15 || y < 0 || y >= normal_terrain_height {
		return air.network_id
	}
	return c.block_id(x, y, z)
}

fn set_tree_block(mut c Chunk, x int, y int, z int, b Block) {
	if x < 0 || x > 15 || z < 0 || z > 15 || y < 0 || y >= normal_terrain_height {
		return
	}
	c.set_block(x, y, z, b)
}

fn tree_ground_y(c &Chunk, x int, z int) int {
	for y := normal_terrain_height - 1; y >= 0; y-- {
		id := c.block_id(x, y, z)
		if tree_soil(id) {
			return y + 1
		}
		if id != air.network_id && id != snow.network_id {
			return -1
		}
	}
	return -1
}

fn populate_trees(mut c Chunk, spec TreeSpec, mut r Random) {
	amount := r.next_range(0, 1) + spec.base_amount
	for _ in 0 .. amount {
		x := r.next_range(0, 15)
		z := r.next_range(0, 15)
		y := tree_ground_y(c, x, z)
		if y == -1 {
			continue
		}
		height := if spec.conifer { r.next_bounded_int(4) + 6 } else { r.next_bounded_int(3) + 4 }
		if !tree_fits(c, x, y, z, height) {
			continue
		}
		trunk_height := if spec.conifer { height - r.next_bounded_int(3) } else { height - 1 }
		place_tree_trunk(mut c, x, y, z, trunk_height, spec.log)
		if spec.conifer {
			place_conifer_canopy(mut c, x, y, z, height, spec.leaves, mut r)
		} else {
			place_broadleaf_canopy(mut c, x, y, z, height, spec.leaves, mut r)
		}
	}
}

fn tree_fits(c &Chunk, x int, y int, z int, height int) bool {
	mut radius := 0
	for yy in 0 .. height + 3 {
		if yy == 1 || yy == height {
			radius++
		}
		for xx in -radius .. radius + 1 {
			for zz in -radius .. radius + 1 {
				if !tree_can_override(chunk_id_or_air(c, x + xx, y + yy, z + zz)) {
					return false
				}
			}
		}
	}
	return true
}

fn place_tree_trunk(mut c Chunk, x int, y int, z int, trunk_height int, log Block) {
	set_tree_block(mut c, x, y - 1, z, dirt)
	for yy in 0 .. trunk_height {
		if tree_can_override(chunk_id_or_air(c, x, y + yy, z)) {
			set_tree_block(mut c, x, y + yy, z, log)
		}
	}
}

fn place_broadleaf_canopy(mut c Chunk, x int, y int, z int, height int, leaves Block, mut r Random) {
	for yy := y - 3 + height; yy <= y + height; yy++ {
		y_offset := yy - (y + height)
		mid := 1 - y_offset / 2
		for xx := x - mid; xx <= x + mid; xx++ {
			x_offset := abs_int(xx - x)
			for zz := z - mid; zz <= z + mid; zz++ {
				z_offset := abs_int(zz - z)
				if x_offset == mid && z_offset == mid
					&& (y_offset == 0 || r.next_bounded_int(2) == 0) {
					continue
				}
				if chunk_id_or_air(c, xx, yy, zz) == air.network_id {
					set_tree_block(mut c, xx, yy, zz, leaves)
				}
			}
		}
	}
}

fn place_conifer_canopy(mut c Chunk, x int, y int, z int, height int, leaves Block, mut r Random) {
	top_size := height - (1 + r.next_bounded_int(2))
	limit_radius := 2 + r.next_bounded_int(2)
	mut radius := r.next_bounded_int(2)
	mut max_radius := 1
	mut min_radius := 0
	for yy in 0 .. top_size + 1 {
		layer_y := y + height - yy
		for xx := x - radius; xx <= x + radius; xx++ {
			x_offset := abs_int(xx - x)
			for zz := z - radius; zz <= z + radius; zz++ {
				z_offset := abs_int(zz - z)
				if x_offset == radius && z_offset == radius && radius > 0 {
					continue
				}
				if chunk_id_or_air(c, xx, layer_y, zz) == air.network_id {
					set_tree_block(mut c, xx, layer_y, zz, leaves)
				}
			}
		}
		if radius >= max_radius {
			radius = min_radius
			min_radius = 1
			max_radius++
			if max_radius > limit_radius {
				max_radius = limit_radius
			}
		} else {
			radius++
		}
	}
}

fn abs_int(v int) int {
	if v < 0 {
		return -v
	}
	return v
}
