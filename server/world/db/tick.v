module db

import rand
import server.block
import server.world

// ScheduledEntry represents one pending scheduled tick for a block position.
// It becomes due when current_tick reaches due.
//
// Multiple entries may be queued for the same position; scheduled ticks are
// not deduplicated.
struct ScheduledEntry {
	x   int
	y   int
	z   int
	due i64
}

struct TickPosition {
	x int
	y int
	z int
}

// block_id returns the block at the given position. It first checks for an
// in memory override, then falls back to the world's configured generator.
//
// This matches the override first lookup used by session.block_at().
pub fn (w &World) block_id(x int, y int, z int) int {
	if id := w.block_override(x, y, z) {
		return id
	}
	return world.new_generator(w.generator_name).block_at(x, y, z)
}

// schedule_tick queues one scheduled tick for the given position.
// ScheduledTicker.scheduled_tick callback runs after delay game ticks.
pub fn (mut w World) schedule_tick(x int, y int, z int, delay int) {
	w.mutex.lock()
	due := w.current_tick + i64(delay)
	w.scheduled << ScheduledEntry{x, y, z, due}
	w.mutex.unlock()
}

// tick advances this world by one game tick: fires every scheduled entry whose delay has elapsed,
// then rolls the random tick chance (see block.random_tick_speed) for every currently overridden block position.
// Only overridden positions are considered.
//
// Returns the positions changed by either pass. World has no session/network knowledge,
// so broadcasting these to connected players is the caller's responsibility.
pub fn (mut w World) tick(registry &block.Registry) []BlockOverride {
	mut changed := []BlockOverride{}

	w.mutex.lock()
	w.current_tick++
	current := w.current_tick
	mut due := []ScheduledEntry{}
	mut pending := []ScheduledEntry{}
	for entry in w.scheduled {
		if entry.due <= current {
			due << entry
		} else {
			pending << entry
		}
	}
	w.scheduled = pending
	mut positions := []TickPosition{cap: w.overrides.len}
	for key, _ in w.overrides {
		parts := key.split(':')
		if parts.len != 3 {
			continue
		}
		positions << TickPosition{
			x: parts[0].int()
			y: parts[1].int()
			z: parts[2].int()
		}
	}
	w.mutex.unlock()

	for entry in due {
		old_id := w.block_id(entry.x, entry.y, entry.z)
		b := registry.get(old_id) or { continue }
		if b is block.ScheduledTicker {
			b.scheduled_tick(entry.x, entry.y, entry.z, mut w)
			new_id := w.block_id(entry.x, entry.y, entry.z)
			if new_id != old_id {
				changed << BlockOverride{
					x:  entry.x
					y:  entry.y
					z:  entry.z
					id: new_id
				}
			}
		}
	}

	for pos in positions {
		chance := rand.intn(block.random_tick_chance_denominator) or { continue }
		if chance >= block.random_tick_speed {
			continue
		}
		old_id := w.block_id(pos.x, pos.y, pos.z)
		b := registry.get(old_id) or { continue }
		if b is block.RandomTicker {
			b.random_tick(pos.x, pos.y, pos.z, mut w)
			new_id := w.block_id(pos.x, pos.y, pos.z)
			if new_id != old_id {
				changed << BlockOverride{
					x:  pos.x
					y:  pos.y
					z:  pos.z
					id: new_id
				}
			}
		}
	}
	return changed
}
