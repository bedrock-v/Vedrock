module world

fn read_u32_le(data []u8, offset int) u32 {
	return u32(data[offset]) | (u32(data[offset + 1]) << 8) | (u32(data[offset + 2]) << 16) | (u32(data[offset + 3]) << 24)
}

fn read_varint_signed(data []u8, offset int) (int, int) {
	mut result := u32(0)
	mut shift := u32(0)
	mut i := offset
	for {
		b := data[i]
		i++
		result |= u32(b & 0x7f) << shift
		if b & 0x80 == 0 {
			break
		}
		shift += 7
	}
	value := int(result >> 1) ^ -int(result & 1)
	return value, i
}

fn decode_paletted(data []u8) ([]u16, []int) {
	mut i := 0
	header := data[i]
	i++
	bits := header >> 1
	mut indices := []u16{}
	if bits != 0 {
		blocks_per_word := 32 / int(bits)
		word_count := (4096 + blocks_per_word - 1) / blocks_per_word
		mask := (u32(1) << bits) - 1
		for _ in 0 .. word_count {
			word := read_u32_le(data, i)
			i += 4
			for slot in 0 .. blocks_per_word {
				if indices.len >= 4096 {
					break
				}
				indices << u16((word >> u32(slot * int(bits))) & mask)
			}
		}
	}
	mut palette_size := 1
	if bits != 0 {
		size, next := read_varint_signed(data, i)
		palette_size = size
		i = next
	}
	mut palette := []int{}
	for _ in 0 .. palette_size {
		value, next := read_varint_signed(data, i)
		palette << value
		i = next
	}
	return indices, palette
}

fn test_bits_per_block_for() {
	assert bits_per_block_for(1) == 0
	assert bits_per_block_for(2) == 1
	assert bits_per_block_for(3) == 2
	assert bits_per_block_for(4) == 2
	assert bits_per_block_for(5) == 3
	assert bits_per_block_for(16) == 4
	assert bits_per_block_for(17) == 5
}

fn test_paletted_single_value() {
	encoded := encode_paletted_storage([]u16{}, [42])
	assert encoded == [u8(1), 84]
}

fn test_paletted_roundtrip() {
	mut indices := []u16{len: 4096}
	for i in 0 .. 4096 {
		indices[i] = u16(i % 3)
	}
	palette := [100, 200, 300]
	encoded := encode_paletted_storage(indices, palette)
	decoded_indices, decoded_palette := decode_paletted(encoded)
	assert decoded_palette == palette
	assert decoded_indices.len == 4096
	for i in 0 .. 4096 {
		assert decoded_indices[i] == indices[i]
	}
}

fn test_void_chunk_matches_empty_payload() {
	chunk := generate_void()
	payload := chunk.serialize()
	assert payload.len == dimension_subchunk_count * 2 + 1
	for s in 0 .. dimension_subchunk_count {
		assert payload[s * 2] == 0x01
		assert payload[s * 2 + 1] == plains_biome_id << 1
	}
	assert payload[payload.len - 1] == 0x00
}

fn test_flat_chunk_structure() {
	chunk := generate_flat()
	assert chunk.section_count() == 8
	payload := chunk.serialize()
	assert payload[0] == 8
	assert payload[1] == 1
	assert payload[payload.len - 1] == 0x00
}

fn test_fnv1a_32_vector() {
	assert fnv1a_32(''.bytes()) == u32(0x811c9dc5)
	assert fnv1a_32('a'.bytes()) == u32(0xe40c292c)
}
