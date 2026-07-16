module world

import math

const noise_hash_offset = u32(2166136261)
const noise_hash_prime = u32(16777619)

fn hash_step(h u32, v u32) u32 {
	return (h ^ v) * noise_hash_prime
}

fn hash_unit(h u32) f64 {
	return f64(h % 1_000_000) / 1_000_000.0
}

// hash3_unit returns a deterministic pseudo random value in [0, 1) for an
// integer (x, y, z, salt) tuple. Used directly for independent per block
// decisions (ore placement) where no smoothing between neighbours is wanted.
fn hash3_unit(x int, y int, z int, salt u32) f64 {
	mut h := noise_hash_offset
	h = hash_step(h, u32(x))
	h = hash_step(h, u32(y))
	h = hash_step(h, u32(z))
	h = hash_step(h, salt)
	return hash_unit(h)
}

fn lattice_value(x int, z int, salt u32) f64 {
	mut h := noise_hash_offset
	h = hash_step(h, u32(x))
	h = hash_step(h, u32(z))
	h = hash_step(h, salt)
	return hash_unit(h)
}

fn lattice_value3d(x int, y int, z int, salt u32) f64 {
	mut h := noise_hash_offset
	h = hash_step(h, u32(x))
	h = hash_step(h, u32(y))
	h = hash_step(h, u32(z))
	h = hash_step(h, salt)
	return hash_unit(h)
}

fn smoothstep(t f64) f64 {
	return t * t * (3.0 - 2.0 * t)
}

// value_noise2d samples smoothed value noise at fractional (x, z), bilinearly
// interpolating between the 4 surrounding integer lattice points. Returns a
// value in [0, 1).
fn value_noise2d(x f64, z f64, salt u32) f64 {
	x0 := int(math.floor(x))
	z0 := int(math.floor(z))
	fx := smoothstep(x - f64(x0))
	fz := smoothstep(z - f64(z0))
	v00 := lattice_value(x0, z0, salt)
	v10 := lattice_value(x0 + 1, z0, salt)
	v01 := lattice_value(x0, z0 + 1, salt)
	v11 := lattice_value(x0 + 1, z0 + 1, salt)
	top := v00 + (v10 - v00) * fx
	bottom := v01 + (v11 - v01) * fx
	return top + (bottom - top) * fz
}

fn value_noise3d(x f64, y f64, z f64, salt u32) f64 {
	x0 := int(math.floor(x))
	y0 := int(math.floor(y))
	z0 := int(math.floor(z))
	fx := smoothstep(x - f64(x0))
	fy := smoothstep(y - f64(y0))
	fz := smoothstep(z - f64(z0))

	v000 := lattice_value3d(x0, y0, z0, salt)
	v100 := lattice_value3d(x0 + 1, y0, z0, salt)
	v010 := lattice_value3d(x0, y0 + 1, z0, salt)
	v110 := lattice_value3d(x0 + 1, y0 + 1, z0, salt)
	v001 := lattice_value3d(x0, y0, z0 + 1, salt)
	v101 := lattice_value3d(x0 + 1, y0, z0 + 1, salt)
	v011 := lattice_value3d(x0, y0 + 1, z0 + 1, salt)
	v111 := lattice_value3d(x0 + 1, y0 + 1, z0 + 1, salt)

	x00 := v000 + (v100 - v000) * fx
	x10 := v010 + (v110 - v010) * fx
	x01 := v001 + (v101 - v001) * fx
	x11 := v011 + (v111 - v011) * fx
	y0v := x00 + (x10 - x00) * fy
	y1v := x01 + (x11 - x01) * fy
	return y0v + (y1v - y0v) * fz
}

// fbm2d sums octaves of value_noise2d (fractal Brownian motion) for a more
// natural looking terrain/biome map than a single noise layer would give.
// Returns a value in [0, 1).
fn fbm2d(x f64, z f64, salt u32, octaves int) f64 {
	mut total := 0.0
	mut amplitude := 1.0
	mut frequency := 1.0
	mut max_amplitude := 0.0
	for i in 0 .. octaves {
		total += value_noise2d(x * frequency, z * frequency, salt + u32(i) * 7919) * amplitude
		max_amplitude += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	}
	return total / max_amplitude
}

fn fbm3d(x f64, y f64, z f64, salt u32, octaves int) f64 {
	mut total := 0.0
	mut amplitude := 1.0
	mut frequency := 1.0
	mut max_amplitude := 0.0
	for i in 0 .. octaves {
		total += value_noise3d(x * frequency, y * frequency, z * frequency, salt + u32(i) * 7919) * amplitude
		max_amplitude += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	}
	return total / max_amplitude
}

fn dist2d(x int, z int) f64 {
	return math.sqrt(f64(x * x + z * z))
}
