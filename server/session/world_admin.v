module session

import server.cmd

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

pub fn (mut s NetworkSession) world_create(name string) ! {
	s.hub.create_world(name)!
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

pub fn (mut c ConsoleSender) world_create(name string) ! {
	c.hub.create_world(name)!
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
		overrides:  info.overrides
		is_default: info.is_default
		players:    info.players
	}
}
