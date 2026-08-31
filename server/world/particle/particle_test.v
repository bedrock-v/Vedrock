module particle

import bedrock_v.protocol.current as proto

fn test_block_break_carries_the_runtime_id() {
	p := BlockBreak{
		block_runtime_id: 42
	}
	assert p.event_id() == proto.level_event_particles_destroy_block
	assert p.data() == 42
}

fn test_punch_block_packs_the_face_above_the_runtime_id() {
	p := PunchBlock{
		block_runtime_id: 42
		face:             3
	}
	assert p.event_id() == proto.level_event_particles_punch_block
	assert p.data() == 42 | int(u32(3) << 24)
}

fn test_custom_passes_the_event_through() {
	p := Custom{
		id:      1234
		payload: 7
	}
	assert p.event_id() == 1234
	assert p.data() == 7
}
