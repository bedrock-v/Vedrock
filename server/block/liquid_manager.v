module block

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

// lava_tick_divisor is how many liquid ticks pass between two steps of a lava
// cell. Lava crawls where water runs, and this is the whole difference.
pub const lava_tick_divisor = 6

// LiquidManager owns the set of block positions that still need a liquid
// update and processes them on the actor thread each tick. It holds no world
// of its own - the Host it is handed reads and writes blocks.
@[heap]
pub struct LiquidManager {
mut:
	host    Host
	pending map[string]Pos
	air_id  int
	// ticks counts the liquid ticks this manager has run, so lava can be held
	// back to its own slower rate without a second queue.
	ticks i64
}

// new_manager builds a LiquidManager bound to host.
pub fn new_manager(host Host) &LiquidManager {
	return &LiquidManager{
		host:   host
		air_id: world.air.network_id
	}
}

fn key(x int, y int, z int) string {
	return '${x},${y},${z}'
}

// place_source sets a water source at the position and queues it for spreading.
pub fn (mut m LiquidManager) place_source(x int, y int, z int) {
	m.place_liquid_source(.water, x, y, z)
}

// place_liquid_source sets a source of the given fluid and queues it for
// spreading.
pub fn (mut m LiquidManager) place_liquid_source(kind LiquidKind, x int, y int, z int) {
	m.host.set_block_id(new_liquid_source(kind).network_id(), x, y, z)
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

// liquid_at returns the resolved liquid cell at a position, or none if the
// block there is not a liquid.
fn (mut m LiquidManager) liquid_at(x int, y int, z int) ?LiquidState {
	return liquid_at_id(m.host.get_block(x, y, z))
}

// liquid_of_kind_at returns the cell at a position only when it holds the
// fluid asked for.
fn (mut m LiquidManager) liquid_of_kind_at(kind LiquidKind, x int, y int, z int) ?LiquidState {
	state := m.liquid_at(x, y, z) or { return none }
	if state.kind != kind {
		return none
	}
	return state
}

// is_liquid_of_kind reports whether the block at a position is that fluid.
fn (mut m LiquidManager) is_liquid_of_kind(kind LiquidKind, x int, y int, z int) bool {
	if _ := m.liquid_of_kind_at(kind, x, y, z) {
		return true
	}
	return false
}

// can_flow_into reports whether a liquid may spread into the cell. Air and any
// liquid are replaceable - solid terrain blocks the flow.
fn (mut m LiquidManager) can_flow_into(x int, y int, z int) bool {
	id := m.host.get_block(x, y, z)
	if id == m.air_id {
		return true
	}
	return id in liquid_states
}

// tick drains up to max_cells_per_tick queued cells and processes each. Cells a
// processed cell touches (neighbours it fills, or itself when it changes) are
// re-queued for the next call, so the flow advances one ring per call. The
// world runtime only calls this every few ticks, which is what sets the vanilla
// flow rate. Lava is held back further, to its own slower rate. Runs on the
// owning world's actor thread.
pub fn (mut m LiquidManager) tick() {
	m.ticks++
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
	lava_moves := m.ticks % lava_tick_divisor == 0
	for p in batch {
		if !lava_moves && m.is_liquid_of_kind(.lava, p.x, p.y, p.z) {
			// Hold the cell over rather than dropping it: lava still has to
			// move, just not on this tick.
			m.enqueue(p.x, p.y, p.z)
			continue
		}
		m.process(p.x, p.y, p.z)
	}
}

// process runs one cell's flow step: dry up if unfed, fall straight down, then
// spread outwards with decayed depth.
fn (mut m LiquidManager) process(x int, y int, z int) {
	cur := m.liquid_at(x, y, z) or { return }
	if m.solidified_by_contact(cur, x, y, z) {
		return
	}

	// A flowing cell with no feeding source nearby dries up toward air.
	if !cur.is_source() && !m.source_around(cur, x, y, z) {
		decay := cur.spread_decay()
		mut next_depth := 0
		if cur.depth - 2 * decay > 0 {
			next_depth = cur.depth - 2 * decay
		}
		if next_depth <= 0 {
			m.set_air(x, y, z)
		} else {
			m.set_liquid(new_liquid_flowing(cur.kind, next_depth), x, y, z)
			m.enqueue_neighbours(x, y, z)
		}
		return
	}

	// Falling: pour straight down into air/liquid below.
	below_falls := m.can_flow_into(x, y - 1, z)
	if below_falls {
		m.flow_into(new_liquid_falling(cur.kind), x, y - 1, z)
	}

	// Once resting on ground (or a source), spread outwards with decayed depth.
	if cur.is_source() || !below_falls {
		spread_depth := cur.depth - cur.spread_decay()
		if spread_depth <= 0 {
			return
		}
		m.spread_outwards(new_liquid_flowing(cur.kind, spread_depth), x, y, z)
	}
}

// solidified_by_contact turns a lava cell that has met water into the rock the
// contact makes, and reports whether it did. A lava source becomes obsidian, a
// flowing one cobblestone - the same two outcomes as in game, decided by which
// of the two the lava was.
fn (mut m LiquidManager) solidified_by_contact(cur LiquidState, x int, y int, z int) bool {
	if cur.kind != .lava || !m.water_touching(x, y, z) {
		return false
	}
	solid := if cur.is_source() { world.obsidian } else { world.cobblestone }
	m.host.set_block_id(solid.network_id, x, y, z)
	m.enqueue_neighbours(x, y, z)
	return true
}

// water_touching reports whether any face neighbour of a cell holds water.
fn (mut m LiquidManager) water_touching(x int, y int, z int) bool {
	return m.is_liquid_of_kind(.water, x + 1, y, z) || m.is_liquid_of_kind(.water, x - 1, y, z)
		|| m.is_liquid_of_kind(.water, x, y, z + 1) || m.is_liquid_of_kind(.water, x, y, z - 1)
		|| m.is_liquid_of_kind(.water, x, y + 1, z) || m.is_liquid_of_kind(.water, x, y - 1, z)
}

// spread_outwards flows the decayed liquid into each horizontal neighbour.
fn (mut m LiquidManager) spread_outwards(l LiquidState, x int, y int, z int) {
	m.flow_into(l, x + 1, y, z)
	m.flow_into(l, x - 1, y, z)
	m.flow_into(l, x, y, z + 1)
	m.flow_into(l, x, y, z - 1)
}

// flow_into writes l into the target cell if it may flow there and the target
// isn't already an equal-or-fuller cell of the same fluid, then queues the
// target. Flowing into the opposite fluid makes rock instead.
fn (mut m LiquidManager) flow_into(l LiquidState, x int, y int, z int) {
	if !m.can_flow_into(x, y, z) {
		return
	}
	if existing := m.liquid_at(x, y, z) {
		if existing.kind != l.kind {
			m.mix_into(l, existing, x, y, z)
			return
		}
		// Don't overwrite an equal or fuller cell and never demote a source or
		// a falling column
		if existing.is_source() {
			return
		}
		if existing.falling && !l.falling {
			return
		}
		if !l.falling && existing.depth >= l.depth && !existing.falling {
			return
		}
	}
	m.set_liquid(l, x, y, z)
	m.enqueue(x, y, z)
}

// mix_into resolves one fluid arriving where the other already is. Lava
// arriving in water sets into stone; water arriving in lava makes obsidian of
// a source and cobblestone of anything flowing.
fn (mut m LiquidManager) mix_into(arriving LiquidState, existing LiquidState, x int, y int, z int) {
	solid := if arriving.kind == .lava {
		world.stone
	} else if existing.is_source() {
		world.obsidian
	} else {
		world.cobblestone
	}
	m.host.set_block_id(solid.network_id, x, y, z)
	m.enqueue_neighbours(x, y, z)
}

// source_around reports whether a horizontally adjacent or overhead cell of the
// same fluid feeds this one. A cell fed from above (falling) or by a fuller
// neighbour stays wet; otherwise it dries up. Also counts adjacent sources for
// source-forming, which only water does.
fn (mut m LiquidManager) source_around(cur LiquidState, x int, y int, z int) bool {
	// Liquid directly above feeds this cell (it is falling into it).
	if m.is_liquid_of_kind(cur.kind, x, y + 1, z) {
		return true
	}
	mut adjacent_sources := 0
	mut fed := false
	offsets := [[1, 0], [-1, 0], [0, 1], [0, -1]]
	for o in offsets {
		side := m.liquid_of_kind_at(cur.kind, x + o[0], y, z + o[1]) or { continue }
		if side.is_source() {
			adjacent_sources++
		}
		if side.depth > cur.depth {
			fed = true
		}
	}
	// Two adjacent water sources form a new source here if there is solid
	// ground below. Lava never does this.
	if cur.kind == .water && adjacent_sources >= min_adjacent_sources
		&& !m.can_flow_into(x, y - 1, z) {
		m.set_liquid(new_liquid_source(cur.kind), x, y, z)
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

fn (mut m LiquidManager) set_liquid(l LiquidState, x int, y int, z int) {
	m.host.set_block_id(l.network_id(), x, y, z)
}

fn (mut m LiquidManager) set_air(x int, y int, z int) {
	m.host.set_block_id(m.air_id, x, y, z)
	m.enqueue_neighbours(x, y, z)
}
