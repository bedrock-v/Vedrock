module world

import time

// tick_interval is how long one tick lasts: twenty of them to the second.
pub const tick_interval = 50 * time.millisecond

// Ticker is an entity that does something every tick. A world ticks the
// entities it holds that implement this, inside the tick's own transaction.
pub interface Ticker {
	Entity
mut:
	tick(mut tx Tx, current i64)
}

// tick_loop ticks the world until it closes.
//
// Each tick waits for the one before it to finish and a world that runs late
// skips the ticks it missed rather than running them back to back. Ticks are
// dropped, never owed: current_tick counts ticks that happened.
fn (mut wr Runtime) tick_loop() {
	mut next := time.now().add(tick_interval)
	for {
		now := time.now()
		if next > now {
			time.sleep(next - now)
		}
		call[bool](mut wr, 'world.tick', fn (mut tx Tx) !bool {
			tx.tick()
			return true
		}) or { return }
		now_after := time.now()
		next = next.add(tick_interval)
		for next <= now_after {
			next = next.add(tick_interval)
		}
	}
}

// advance_tick ticks the world once and waits for it. A world ticks on its own;
// this is for a caller that wants one tick to have happened before it carries
// on which is mostly a test.
pub fn (mut wr Runtime) advance_tick() ! {
	call[bool](mut wr, 'world.tick', fn (mut tx Tx) !bool {
		tx.tick()
		return true
	})!
}

// tick advances the world by one tick and ticks everything in it.
fn (mut tx Tx) tick() {
	tx.world.current_tick++
	current := tx.world.current_tick
	mut handles := []&Handle{cap: tx.world.entities.len}
	for _, h in tx.world.entities {
		handles << h
	}
	for h in handles {
		held := tx.world.entities[h.id_] or { continue }
		if voidptr(held) != voidptr(h) {
			continue
		}
		mut e := h.entity
		if mut e is Ticker {
			e.tick(mut tx, current)
		}
	}
}

// current_tick is how many ticks this world has run.
pub fn (tx &Tx) current_tick() i64 {
	tx.ensure_live()
	return tx.world.current_tick
}
