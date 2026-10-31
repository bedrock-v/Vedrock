module chunk

// sizes are the bits per index a storage can have. The client reads no others.
const sizes = [0, 1, 2, 3, 4, 5, 6, 8, 16]

// Storage holds a value for each of the 4096 blocks of a section: a palette of
// the values in use and, for every block, its index into the palette packed
// into 32 bit words. Indices never cross a word, so 3, 5 and 6 bits leave the
// top bits of each word unused. With one value there are no words at all.
struct Storage {
mut:
	bits    int
	palette []u32
	words   []u32
}

fn new_storage(v u32) Storage {
	return Storage{
		palette: [v]
	}
}

// block_index is where a block is in a storage. y changes fastest.
fn block_index(x int, y int, z int) int {
	return x << 8 | z << 4 | y
}

fn (s &Storage) at(i int) u32 {
	return s.palette[s.index(i)]
}

fn (mut s Storage) set(i int, v u32) {
	mut index := s.palette.index(v)
	if index < 0 {
		index = s.palette.len
		s.palette << v
		if s.palette.len > 1 << s.bits {
			s.grow()
		}
	}
	s.put(i, index)
}

fn (s &Storage) index(i int) int {
	if s.bits == 0 {
		return 0
	}
	per_word := 32 / s.bits
	shift := u32(i % per_word * s.bits)
	return int((s.words[i / per_word] >> shift) & ((u32(1) << s.bits) - 1))
}

fn (mut s Storage) put(i int, index int) {
	if s.bits == 0 {
		return
	}
	per_word := 32 / s.bits
	shift := u32(i % per_word * s.bits)
	mask := ((u32(1) << s.bits) - 1) << shift
	w := i / per_word
	s.words[w] = (s.words[w] & ~mask) | (u32(index) << shift)
}

// grow moves to the smallest size that holds the palette, keeping the index of
// every block.
fn (mut s Storage) grow() {
	mut indices := []int{len: 4096}
	for i in 0 .. indices.len {
		indices[i] = s.index(i)
	}
	for size in sizes {
		if s.palette.len <= 1 << size {
			s.bits = size
			break
		}
	}
	per_word := 32 / s.bits
	s.words = []u32{len: (4096 + per_word - 1) / per_word}
	for i, index in indices {
		s.put(i, index)
	}
}

fn (s &Storage) same(o &Storage) bool {
	return s.bits == o.bits && s.palette == o.palette && s.words == o.words
}
