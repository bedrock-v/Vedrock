module session

import protocol.types
import server.cmd
import server.world
import server.world.db

// world_admin wires the /world command's needs onto the Hub. Create/delete
// only touch the worlds map (never a player's active world), so they run
// directly on the Hub which already guards that map. Teleport goes through the
// existing TeleportJob so the world swap happens on the actor thread.

pub fn (mut s NetworkSession) world_names() []string {
	return s.hub.list_worlds()
}

pub fn (mut s NetworkSession) world_info(name string) ?cmd.WorldSummary {
	info := s.hub.world_info(name)?
	return to_world_summary(info)
}

pub fn (mut s NetworkSession) world_create(name string, dimension string, generator string) ! {
	dim := world.dimension_by_name(dimension) or {
		return error('unknown dimension "${dimension}"')
	}
	s.hub.create_world(name, dim, generator)!
}

pub fn (mut s NetworkSession) world_load(name string) ! {
	s.hub.load_world(name)!
}

pub fn (mut s NetworkSession) world_delete(name string) ! {
	s.hub.delete_world(name)!
}

pub fn (mut s NetworkSession) world_teleport(name string) ! {
	target := s.hub.world(name) or { return error('world "${name}" is not loaded') }
	gen := target.make_generator(s.hub.build_generator(target))
	pos := world_spawn_position(target, gen)
	s.teleport_to_world(name, pos.x, pos.y, pos.z)
}

pub fn (mut c ConsoleSender) world_names() []string {
	return c.hub.list_worlds()
}

pub fn (mut c ConsoleSender) world_info(name string) ?cmd.WorldSummary {
	info := c.hub.world_info(name)?
	return to_world_summary(info)
}

pub fn (mut c ConsoleSender) world_create(name string, dimension string, generator string) ! {
	dim := world.dimension_by_name(dimension) or {
		return error('unknown dimension "${dimension}"')
	}
	c.hub.create_world(name, dim, generator)!
}

pub fn (mut c ConsoleSender) world_load(name string) ! {
	c.hub.load_world(name)!
}

pub fn (mut c ConsoleSender) world_delete(name string) ! {
	c.hub.delete_world(name)!
}

pub fn (mut c ConsoleSender) world_teleport(name string) ! {
	return error('the console cannot teleport into a world')
}

fn to_world_summary(info WorldInfo) cmd.WorldSummary {
	return cmd.WorldSummary{
		name:       info.name
		generator:  info.generator
		dimension:  info.dimension
		overrides:  info.overrides
		is_default: info.is_default
		players:    info.players
	}
}

fn world_spawn_position(target &db.World, gen world.Generator) types.Vector3 {
	mut y := gen.spawn_y()
	if y < target.dimension.min_y + 1 {
		y = target.dimension.min_y + 1
	}
	max_y := target.dimension.max_y() - 1
	if y > max_y {
		y = max_y
	}
	return types.Vector3{0.0, f32(y) + player_eye_height, 0.0}
}
