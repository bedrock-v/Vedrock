module session

import server.world

struct SetBlockTask {
	x  int
	y  int
	z  int
	id int
}

fn (t SetBlockTask) name() string {
	return 'SetBlockTask'
}

fn (t SetBlockTask) run(mut tx WorldTx) {
	tx.set_block(t.x, t.y, t.z, t.id)
}

// write_block resolves the default world's runtime and submits a
// SetBlockTask. The actual write and world scoped broadcast happen on
// that world's own actor thread via tx.set_block, never here. Reached via
// set_block/set_block_id/restore_area.
fn (mut h Hub) write_block(id int, x int, y int, z int) {
	mut wr := h.default_world_runtime() or { return }
	wr.submit(SetBlockTask{
		x:  x
		y:  y
		z:  z
		id: id
	})
}

// block_id_for resolves a namespaced block name to its network id, or none if
// the name isn't a known block. Air maps to world.air; every other name is
// validated against the item palette (real blocks exist there as items).
fn (h &Hub) block_id_for(name string) ?int {
	if name == 'minecraft:air' {
		return world.air.network_id
	}
	if h.data.item_id(name) == 0 {
		return none
	}
	return world.new_block(name).network_id
}

// set_block sets a block by namespaced id in the default world and broadcasts
// the change. Returns false if name isn't a known block. The name is resolved
// synchronously; the write itself is routed through the actor thread.
fn (mut h Hub) set_block(name string, x int, y int, z int) bool {
	id := h.block_id_for(name) or { return false }
	h.write_block(id, x, y, z)
	return true
}

// get_block returns the block network id at a position in the default world,
// preferring a saved override and otherwise falling back to the generator so
// untouched terrain reads correctly.
fn (mut h Hub) get_block(x int, y int, z int) int {
	mut wld := h.default_world() or { return world.air.network_id }
	if id := wld.block_override(x, y, z) {
		return id
	}
	gen := wld.make_generator(h.build_generator(wld))
	return gen.block_at(x, y, z)
}

fn (mut h Hub) collision_boxes(x int, y int, z int) []world.AABB {
	id := h.get_block(x, y, z)
	if id == world.air.network_id {
		return []world.AABB{}
	}
	if isnil(h.palette) {
		return world.absolute_boxes(world.solid_model(), x, y, z)
	}
	return world.absolute_boxes_with_neighbors(h.palette.model(id), h.neighbor_models(x, y, z), x,
		y, z)
}

fn (mut h Hub) neighbor_models(x int, y int, z int) map[int]world.BlockModel {
	mut out := map[int]world.BlockModel{}
	out[2] = h.palette.model(h.get_block(x, y, z - 1))
	out[3] = h.palette.model(h.get_block(x, y, z + 1))
	out[4] = h.palette.model(h.get_block(x - 1, y, z))
	out[5] = h.palette.model(h.get_block(x + 1, y, z))
	return out
}

// set_block_id writes a raw block network id, used by arena restore. It routes
// through the same actor-thread write path as set_block.
fn (mut h Hub) set_block_id(id int, x int, y int, z int) {
	h.write_block(id, x, y, z)
}

// PlaceWaterTask is place_water's actual per world work. The liquid manager
// interaction only ever happens on the owning world's own actor thread,
// through the WorldTx it's handed.
struct PlaceWaterTask {
	x int
	y int
	z int
}

fn (t PlaceWaterTask) name() string {
	return 'PlaceWaterTask'
}

fn (t PlaceWaterTask) run(mut tx WorldTx) {
	tx.place_water(t.x, t.y, t.z)
}

// place_water sets a water source in the default world and lets that world's
// runtime own the liquid update.
fn (mut h Hub) place_water(x int, y int, z int) {
	mut wr := h.default_world_runtime() or { return }
	wr.submit(PlaceWaterTask{
		x: x
		y: y
		z: z
	})
}

// BlockChangedTask is on_block_changed's actual per world work.
struct BlockChangedTask {
	x int
	y int
	z int
}

fn (t BlockChangedTask) name() string {
	return 'BlockChangedTask'
}

fn (t BlockChangedTask) run(mut tx WorldTx) {
	tx.on_block_changed(t.x, t.y, t.z)
}

// on_block_changed notifies the default world's liquid manager. Dropping under
// queue pressure is acceptable; the next liquid tick will re-check queued water
// state.
fn (mut h Hub) on_block_changed(x int, y int, z int) {
	mut wr := h.default_world_runtime() or { return }
	wr.try_submit(BlockChangedTask{
		x: x
		y: y
		z: z
	})
}

// capture_area snapshots the block ids over the box between the two corners in
// the default world. See world.max_volume for the size cap. This is a plain
// synchronous read against Hub.get_block, not a WorldTask, so it never
// competes with the world's own task queue - only restoring needs the
// budgeted treatment below.
fn (mut h Hub) capture_area(x1 int, y1 int, z1 int, x2 int, y2 int, z2 int) ?&world.Snapshot {
	return world.capture(mut h, world.new_box(x1, y1, z1, x2, y2, z2)) or { return none }
}

// arena_restore_batch_size limits how many blocks one restore task writes
// before yielding to other work queued for the world.
const arena_restore_batch_size = 4096

// ArenaRestoreTask restores a snapshot in bounded batches, then resubmits
// itself for the remaining blocks so movement, combat and ticks can run
// between batches.
struct ArenaRestoreTask {
	snapshot &world.Snapshot
	next     int
}

fn (t ArenaRestoreTask) name() string {
	return 'ArenaRestoreTask'
}

fn (t ArenaRestoreTask) run(mut tx WorldTx) {
	total := t.snapshot.len()
	end := if t.next + arena_restore_batch_size > total {
		total
	} else {
		t.next + arena_restore_batch_size
	}
	for i := t.next; i < end; i++ {
		entry := t.snapshot.entry_at(i)
		tx.set_block(entry.x, entry.y, entry.z, entry.id)
	}
	if end >= total {
		return
	}
	tx.resubmit(ArenaRestoreTask{ snapshot: t.snapshot, next: end })
}

fn (mut h Hub) restore_area(snapshot &world.Snapshot) {
	mut wr := h.default_world_runtime() or { return }
	wr.submit(ArenaRestoreTask{
		snapshot: snapshot
		next:     0
	})
}
