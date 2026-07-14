module liquid

import server.world

// BlockSource reads block network ids from a world by absolute coordinates.
// Hub satisfies it structurally; tests use an in-memory grid.
pub interface BlockSource {
mut:
	get_block(x int, y int, z int) int
}

// BlockSink writes a block by network id and broadcasts the change to viewers.
// Every liquid write routes through this so a spread looks like a normal edit.
pub interface BlockSink {
mut:
	set_block_id(id int, x int, y int, z int)
}

// Host is what the LiquidManager needs from its world: read and write blocks.
// Hub satisfies it via get_block/set_block_id, so this module never imports
// session and stays unit-testable against a fake grid.
pub interface Host {
	BlockSource
	BlockSink
}

// max_cells_per_tick caps how many pending cells the manager drains in a single
// tick so a large flood can never stall the actor thread. Cells left over stay
// queued and are processed on later ticks - the flow just spreads a bit slower
// under heavy load instead of blocking the whole server. 4096 is generous: a
// flat pool spreading 7 cells in every direction is well under this.
pub const max_cells_per_tick = 4096

// Pos is an absolute block coordinate used as a queue key.
struct Pos {
	x int
	y int
	z int
}

// LiquidManager owns the set of block positions that still need a liquid
// update and processes them on the actor thread each tick. It holds no world
// of its own - the Host it is handed reads and writes blocks.
@[heap]
pub struct LiquidManager {
mut:
	host    Host
	pending map[string]Pos
	// water_states maps every known water network id to its resolved cell so the
	// manager can tell water apart from other blocks when it reads the world.
	water_states map[int]WaterState
	air_id       int
}

// new_manager builds a LiquidManager bound to host and precomputes the water id
// table (all source, flowing and falling states) once.
pub fn new_manager(host Host) &LiquidManager {
	mut states := map[int]WaterState{}
	src := new_source()
	states[src.network_id()] = src
	fall := new_falling()
	states[fall.network_id()] = fall
	for depth := 1; depth <= max_flow_depth; depth++ {
		w := new_flowing(depth)
		states[w.network_id()] = w
	}
	return &LiquidManager{
		host:         host
		water_states: states
		air_id:       world.air.network_id
	}
}

fn key(x int, y int, z int) string {
	return '${x},${y},${z}'
}

// place_source sets a water source at the position and queues it for spreading.
pub fn (mut m LiquidManager) place_source(x int, y int, z int) {
	m.host.set_block_id(new_source().network_id(), x, y, z)
	m.enqueue(x, y, z)
}

// enqueue marks a cell as needing a liquid update on a later tick.
pub fn (mut m LiquidManager) enqueue(x int, y int, z int) {
	m.pending[key(x, y, z)] = Pos{x, y, z}
}

// on_block_changed re-evaluates a cell and its neighbours after a block edit -
// placing water starts its flow, breaking a block frees a path for adjacent
// water to spread into. Only water cells actually do anything when processed.
pub fn (mut m LiquidManager) on_block_changed(x int, y int, z int) {
	m.enqueue(x, y, z)
	m.enqueue_neighbours(x, y, z)
}

// pending_count is the number of cells still queued. Used by tests.
pub fn (m &LiquidManager) pending_count() int {
	return m.pending.len
}

// water_at returns the resolved water cell at a position, or none if the block
// there is not water.
fn (mut m LiquidManager) water_at(x int, y int, z int) ?WaterState {
	id := m.host.get_block(x, y, z)
	return m.water_states[id] or { return none }
}

// is_water reports whether the block at a position is any water cell.
fn (mut m LiquidManager) is_water(x int, y int, z int) bool {
	if _ := m.water_at(x, y, z) {
		return true
	}
	return false
}

// can_flow_into reports whether water may spread into the cell. For now only
// air and existing water are replaceable - solid terrain blocks the flow.
fn (mut m LiquidManager) can_flow_into(x int, y int, z int) bool {
	id := m.host.get_block(x, y, z)
	if id == m.air_id {
		return true
	}
	return id in m.water_states
}

// tick drains up to max_cells_per_tick queued cells and processes each. Cells a
// processed cell touches (neighbours it fills, or itself when it changes) are
// re-queued for the next tick, so the flow advances one ring per tick like
// vanilla. Runs on the actor thread from TickJob.
pub fn (mut m LiquidManager) tick() {
	if m.pending.len == 0 {
		return
	}
	mut batch := []Pos{cap: m.pending.len}
	for _, p in m.pending {
		batch << p
		if batch.len >= max_cells_per_tick {
			break
		}
	}
	for p in batch {
		m.pending.delete(key(p.x, p.y, p.z))
	}
	for p in batch {
		m.process(p.x, p.y, p.z)
	}
}

// process runs one cell's flow step: dry up if unfed, fall straight down, then
// spread outwards with decayed depth.
fn (mut m LiquidManager) process(x int, y int, z int) {
	cur := m.water_at(x, y, z) or { return }

	// A flowing cell with no feeding source nearby dries up toward air.
	if !cur.is_source() && !m.source_around(cur, x, y, z) {
		mut next_depth := 0
		if cur.depth - 2 * spread_decay > 0 {
			next_depth = cur.depth - 2 * spread_decay
		}
		if next_depth <= 0 {
			m.set_air(x, y, z)
		} else {
			m.set_water(new_flowing(next_depth), x, y, z)
			m.enqueue_neighbours(x, y, z)
		}
		return
	}

	// Falling: pour straight down into air/water below.
	below_falls := m.can_flow_into(x, y - 1, z)
	if below_falls {
		m.flow_into(new_falling(), x, y - 1, z)
	}

	// Once resting on ground (or a source), spread outwards with decayed depth.
	if cur.is_source() || !below_falls {
		spread_depth := cur.depth - spread_decay
		if spread_depth <= 0 {
			return
		}
		m.spread_outwards(new_flowing(spread_depth), x, y, z)
	}
}

// spread_outwards flows the decayed water into each horizontal neighbour.
fn (mut m LiquidManager) spread_outwards(w WaterState, x int, y int, z int) {
	m.flow_into(w, x + 1, y, z)
	m.flow_into(w, x - 1, y, z)
	m.flow_into(w, x, y, z + 1)
	m.flow_into(w, x, y, z - 1)
}

// flow_into writes w into the target cell if it may flow there and the target
// isn't already an equal-or-fuller water cell, then queues the target.
fn (mut m LiquidManager) flow_into(w WaterState, x int, y int, z int) {
	if !m.can_flow_into(x, y, z) {
		return
	}
	if existing := m.water_at(x, y, z) {
		// Don't overwrite an equal-or-fuller cell, and never demote a source.
		if existing.is_source() {
			return
		}
		if !w.falling && existing.depth >= w.depth && !existing.falling {
			return
		}
	}
	m.set_water(w, x, y, z)
	m.enqueue(x, y, z)
}

// source_around reports whether a horizontally adjacent or overhead water cell
// feeds this one. A cell fed from above (falling) or by a fuller neighbour stays
// wet; otherwise it dries up. Also counts adjacent sources for source-forming.
fn (mut m LiquidManager) source_around(cur WaterState, x int, y int, z int) bool {
	// Water directly above feeds this cell (it is falling into it).
	if m.is_water(x, y + 1, z) {
		return true
	}
	mut adjacent_sources := 0
	mut fed := false
	offsets := [[1, 0], [-1, 0], [0, 1], [0, -1]]
	for o in offsets {
		side := m.water_at(x + o[0], y, z + o[1]) or { continue }
		if side.is_source() {
			adjacent_sources++
		}
		if side.depth > cur.depth {
			fed = true
		}
	}
	// Two adjacent sources form a new source here if there is solid ground below.
	if adjacent_sources >= min_adjacent_sources && !m.can_flow_into(x, y - 1, z) {
		m.set_water(new_source(), x, y, z)
		m.enqueue_neighbours(x, y, z)
		return true
	}
	return fed
}

// enqueue_neighbours queues the six face neighbours of a cell for update.
fn (mut m LiquidManager) enqueue_neighbours(x int, y int, z int) {
	m.enqueue(x + 1, y, z)
	m.enqueue(x - 1, y, z)
	m.enqueue(x, y, z + 1)
	m.enqueue(x, y, z - 1)
	m.enqueue(x, y + 1, z)
	m.enqueue(x, y - 1, z)
}

fn (mut m LiquidManager) set_water(w WaterState, x int, y int, z int) {
	m.host.set_block_id(w.network_id(), x, y, z)
}

fn (mut m LiquidManager) set_air(x int, y int, z int) {
	m.host.set_block_id(m.air_id, x, y, z)
	m.enqueue_neighbours(x, y, z)
}
