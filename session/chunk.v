module session

pub const overworld_subchunk_count = 24
pub const plains_biome_id = u8(1)

fn empty_chunk_payload() []u8 {
	mut payload := []u8{}
	for _ in 0 .. overworld_subchunk_count {
		payload << 0x01
		payload << (plains_biome_id << 1)
	}
	payload << 0x00
	return payload
}
