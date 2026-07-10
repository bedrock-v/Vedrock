module session

import protocol

struct SetDifficultyJob {
	value int
}

fn (j SetDifficultyJob) run(mut h Hub) {
	h.difficulty = j.value
	h.broadcast(&protocol.SetDifficultyPacket{
		difficulty: j.value
	})
}

pub fn (mut s NetworkSession) set_difficulty(value int) {
	s.hub.submit(SetDifficultyJob{
		value: value
	})
}

pub fn (mut c ConsoleSender) set_difficulty(value int) {
	c.hub.submit(SetDifficultyJob{
		value: value
	})
}
