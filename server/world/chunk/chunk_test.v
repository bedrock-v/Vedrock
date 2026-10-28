module chunk

fn test_an_air_chunk_encodes_as_biomes_only() {
	mut want := [u8(0x01), 0x00]
	for _ in 1 .. overworld_sections {
		want << 0xff
	}
	want << 0x00
	assert new().encode() == want
}
