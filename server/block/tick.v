module block

// TickWorld provides the world operations available during block ticks.
// It allows tick handlers to read blocks, including neighbouring positions,
// update blocks and schedule a future tick for a position.
pub interface TickWorld {
	block_id(x int, y int, z int) int
	set_block(x int, y int, z int, id int)
	schedule_tick(x int, y int, z int, delay int)
}

// RandomTicker is implemented by blocks that may receive random updates.
// On each game tick, every eligible block position has a
// random_tick_speed / random_tick_chance_denominator chance of having random_tick called.
//
// Examples include crop growth and leaf decay.
pub interface RandomTicker {
	random_tick(x int, y int, z int, mut w TickWorld)
}

// ScheduledTicker is implemented by blocks that need to perform a one time
// update after a delay. scheduled_tick is called delay game ticks after the
// block position is queued using TickWorld.schedule_tick.
//
// Examples include liquid spreading and delayed redstone propagation.
pub interface ScheduledTicker {
	scheduled_tick(x int, y int, z int, mut w TickWorld)
}

// Each loaded 16x16x16 subchunk contains 4096 block positions.
// On every game tick, vanilla selects random_tick_speed positions from each
// subchunk for random ticking. Therefore, any individual position has a
// random_tick_speed / 4096 chance of being selected per tick.
pub const random_tick_speed = 3
pub const random_tick_chance_denominator = 4096
