module session

import protocol
import server.conf

struct SetDifficultyJob {
	value int
}

fn (j SetDifficultyJob) run(mut h Hub) {
	h.difficulty = j.value
	h.broadcast(&protocol.SetDifficultyPacket{
		difficulty: j.value
	})
	conf.update_difficulty_in_file(h.conf_file, conf.difficulty_name(j.value)) or {
		eprintln('Failed to persist difficulty to ${h.conf_file}: ${err}')
	}
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
