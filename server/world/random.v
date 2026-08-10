module world

// Random is a xorshift128 pseudo random generator. Chunk population has to be
// reproducible, so populators seed one of these from the chunk coordinates
// alone rather than drawing from a shared global source.
pub struct Random {
mut:
	x u32
	y u32
	z u32
	w u32
}

pub fn new_random(seed u32) Random {
	mut r := Random{}
	r.set_seed(seed)
	return r
}

pub fn (mut r Random) set_seed(seed u32) {
	r.x = u32(123456789) ^ seed
	r.y = u32(362436069) ^ (seed << 17) ^ (seed >> 15)
	r.z = u32(521288629) ^ (seed << 31) ^ (seed >> 1)
	r.w = u32(88675123) ^ (seed << 18) ^ (seed >> 14)
}

fn (mut r Random) next_u32() u32 {
	t := r.x ^ (r.x << 11)
	r.x = r.y
	r.y = r.z
	r.z = r.w
	r.w = r.w ^ (r.w >> 19) ^ t ^ (t >> 8)
	return r.w
}

// next_int returns a non negative value spread over the full positive int range.
pub fn (mut r Random) next_int() int {
	return int(r.next_u32() & 0x7fffffff)
}

pub fn (mut r Random) next_float() f64 {
	return f64(r.next_int()) / f64(0x7fffffff)
}

pub fn (mut r Random) next_bounded_int(bound int) int {
	if bound <= 0 {
		return 0
	}
	return r.next_int() % bound
}

// next_range returns a value in [start, end].
pub fn (mut r Random) next_range(start int, end int) int {
	if end <= start {
		return start
	}
	return start + r.next_int() % (end + 1 - start)
}
