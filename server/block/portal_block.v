module block

import server.world

pub struct PortalBlock {
	UnbreakableBlock
}

pub fn new_portal_block() PortalBlock {
	return PortalBlock{
		UnbreakableBlock: UnbreakableBlock{
			id:            'minecraft:portal'
			block_runtime: world.portal_block.network_id
		}
	}
}

pub fn (b PortalBlock) scheduled_tick(x int, y int, z int, mut w TickWorld) {
	if !is_in_valid_frame(x, y, z, mut w) {
		w.set_block(x, y, z, world.air.network_id)
		return
	}
	w.schedule_tick(x, y, z, 1)
}

fn is_portal(id int) bool {
	return id == world.portal_block.network_id
		|| id == world.portal_block_x.network_id
		|| id == world.portal_block_z.network_id
}

fn is_in_valid_frame(x int, y int, z int, mut w TickWorld) bool {
	obsidian_id := world.obsidian.network_id
	air_id := world.air.network_id

	has_x := is_portal(w.block_id(x - 1, y, z)) || is_portal(w.block_id(x + 1, y, z))
	has_z := is_portal(w.block_id(x, y, z - 1)) || is_portal(w.block_id(x, y, z + 1))

	if !has_x && !has_z {
		obs_x := w.block_id(x - 1, y, z) == obsidian_id
			|| w.block_id(x + 1, y, z) == obsidian_id
		obs_z := w.block_id(x, y, z - 1) == obsidian_id
			|| w.block_id(x, y, z + 1) == obsidian_id
		return obs_x && obs_z
	}

	if has_x {
		return w.block_id(x, y, z - 1) == obsidian_id
			|| w.block_id(x, y, z + 1) == obsidian_id
			|| is_obsidian_or_frame(x, y, z, obsidian_id, air_id, mut w)
	}
	return w.block_id(x - 1, y, z) == obsidian_id
		|| w.block_id(x + 1, y, z) == obsidian_id
		|| is_obsidian_or_frame(x, y, z, obsidian_id, air_id, mut w)
}

fn is_obsidian_or_frame(x int, y int, z int, obsidian_id int, air_id int, mut w TickWorld) bool {
	mut has_top := false
	for dy := 1; dy <= 22; dy++ {
		id := w.block_id(x, y + dy, z)
		if id == obsidian_id { has_top = true; break }
		if !is_portal(id) && id != air_id { break }
	}
	mut has_bottom := false
	for dy := 1; dy <= 22; dy++ {
		id := w.block_id(x, y - dy, z)
		if id == obsidian_id { has_bottom = true; break }
		if !is_portal(id) && id != air_id { break }
	}
	return has_top && has_bottom
}
