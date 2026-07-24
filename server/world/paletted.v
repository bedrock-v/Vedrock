module world

const allowed_bits_per_block = [u8(1), 2, 3, 4, 5, 6, 8, 16]

fn bits_per_block_for(palette_size int) u8 {
	if palette_size <= 1 {
		return 0
	}
	for bits in allowed_bits_per_block {
		if (1 << bits) >= palette_size {
			return bits
		}
	}
	return 16
}

fn encode_paletted_storage(indices []u16, palette []int) []u8 {
	bits_per_block := bits_per_block_for(palette.len)
	mut out := []u8{}
	out << (bits_per_block << 1) | 1
	if bits_per_block > 0 {
		blocks_per_word := 32 / int(bits_per_block)
		word_count := (indices.len + blocks_per_word - 1) / blocks_per_word
		for w in 0 .. word_count {
			mut word := u32(0)
			for slot in 0 .. blocks_per_word {
				position := w * blocks_per_word + slot
				if position >= indices.len {
					break
				}
				word |= u32(indices[position]) << u32(slot * int(bits_per_block))
			}
			put_u32_le(mut out, word)
		}
	}
	if bits_per_block != 0 {
		put_varint_signed(mut out, palette.len)
	}
	for entry in palette {
		put_varint_signed(mut out, entry)
	}
	return out
}

fn put_u32_le(mut b []u8, value u32) {
	b << u8(value & 0xff)
	b << u8((value >> 8) & 0xff)
	b << u8((value >> 16) & 0xff)
	b << u8((value >> 24) & 0xff)
}

fn put_varint_signed(mut b []u8, value int) {
	sign_mask := if value < 0 { u32(0xffffffff) } else { u32(0) }
	mut encoded := (u32(value) << 1) ^ sign_mask
	for {
		if encoded & ~u32(0x7f) == 0 {
			b << u8(encoded)
			break
		}
		b << u8((encoded & 0x7f) | 0x80)
		encoded >>= 7
	}
}
