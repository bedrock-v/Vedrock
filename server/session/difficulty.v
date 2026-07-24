module session

import protocol
import server.conf

// set_difficulty mutates the server global difficulty under config_mutex, then
// broadcasts and persists outside the lock.
pub fn (mut h Hub) set_difficulty(value int) {
	h.config_mutex.lock()
	h.difficulty = value
	h.config_mutex.unlock()
	h.broadcast(&protocol.SetDifficultyPacket{
		difficulty: value
	})
	conf.update_difficulty_in_file(h.conf_file, conf.difficulty_name(value)) or {
		eprintln('Failed to persist difficulty to ${h.conf_file}: ${err}')
	}
}

// difficulty_value is the locked read path used by join and respawn packets.
pub fn (mut h Hub) difficulty_value() int {
	h.config_mutex.lock()
	defer {
		h.config_mutex.unlock()
	}
	return h.difficulty
}

pub fn (mut s NetworkSession) set_difficulty(value int) {
	s.hub.set_difficulty(value)
}

pub fn (mut c ConsoleSender) set_difficulty(value int) {
	c.hub.set_difficulty(value)
}
