module session

import server.cmd
import server.world

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
	if _ := s.hub.world(name) {
		x, y, z := s.position()
		s.teleport_to_world(name, x, y, z)
		return
	}
	return error('world "${name}" is not loaded')
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
