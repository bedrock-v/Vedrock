module session

import protocol
import protocol.types
import server.world
import server.arena

// SetBlockJob is the plugin/command block write as a WorldJob. Like every other
// cross-session mutation it runs on the actor thread, so it reuses the same
// world+broadcast path break_block/place_block use without racing them.
struct SetBlockJob {
	x  int
	y  int
	z  int
	id int
}

fn (j SetBlockJob) run(mut h Hub) {
	h.write_block(j.id, j.x, j.y, j.z)
}

// write_block sets a block id in the default world and broadcasts the update to
// every viewer. Actor-thread only - reached via SetBlockJob or restore_area,
// both of which run on run_jobs().
fn (mut h Hub) write_block(id int, x int, y int, z int) {
	if mut wld := h.default_world() {
		wld.set_block(x, y, z, id)
	}
	h.broadcast(&protocol.UpdateBlockPacket{
		block_position:   types.BlockPosition{x, y, z}
		block_runtime_id: id
		flags:            block_update_flags
		data_layer_id:    0
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
pub fn (mut h Hub) set_block(name string, x int, y int, z int) bool {
	id := h.block_id_for(name) or { return false }
	h.submit(SetBlockJob{
		x:  x
		y:  y
		z:  z
		id: id
	})
	return true
}

// get_block returns the block network id at a position in the default world,
// preferring a saved override and otherwise falling back to the generator so
// untouched terrain reads correctly.
pub fn (mut h Hub) get_block(x int, y int, z int) int {
	mut wld := h.default_world() or { return world.air.network_id }
	if id := wld.block_override(x, y, z) {
		return id
	}
	gen := wld.make_generator(world.new_generator(h.world_generator))
	return gen.block_at(x, y, z)
}

pub fn (mut h Hub) collision_boxes(x int, y int, z int) []world.AABB {
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
pub fn (mut h Hub) set_block_id(id int, x int, y int, z int) {
	h.submit(SetBlockJob{
		x:  x
		y:  y
		z:  z
		id: id
	})
}

// PlaceWaterJob places a water source and starts its spread on the actor thread.
struct PlaceWaterJob {
	x int
	y int
	z int
}

fn (j PlaceWaterJob) run(mut h Hub) {
	h.liquids.place_source(j.x, j.y, j.z)
}

// place_water sets a water source at the position and enqueues the spread. The
// write and every spread step run on the actor thread via the liquid tick.
pub fn (mut h Hub) place_water(x int, y int, z int) {
	h.submit(PlaceWaterJob{
		x: x
		y: y
		z: z
	})
}

// BlockChangedJob re-evaluates a cell and its neighbours for liquid flow.
struct BlockChangedJob {
	x int
	y int
	z int
}

fn (j BlockChangedJob) run(mut h Hub) {
	h.liquids.on_block_changed(j.x, j.y, j.z)
}

// on_block_changed notifies the liquid manager that a block edit happened so
// nearby water re-evaluates its flow. Cheap and non-blocking - dropped under a
// full actor queue since the periodic liquid tick will catch up anyway.
pub fn (mut h Hub) on_block_changed(x int, y int, z int) {
	h.try_submit(BlockChangedJob{
		x: x
		y: y
		z: z
	})
}

// capture_area snapshots the block ids over the box between the two corners in
// the default world. See arena.max_volume for the size cap.
pub fn (mut h Hub) capture_area(x1 int, y1 int, z1 int, x2 int, y2 int, z2 int) ?&arena.Snapshot {
	return arena.capture(mut h, arena.new_box(x1, y1, z1, x2, y2, z2)) or { return none }
}

// restore_area writes a snapshot back through the block write path so viewers
// see the arena reset.
pub fn (mut h Hub) restore_area(snapshot &arena.Snapshot) {
	snapshot.restore(mut h)
}
