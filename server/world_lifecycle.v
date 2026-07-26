module server

import server.session
import server.world

// WorldConfig is what load_world needs to bring a world up: its name,
// dimension and which registered generator to use.
//
// dimension/generator_name only matter the first time this name is
// created on disk. Reopening an existing world just reuses whatever
// generator/dimension it was saved with.
//
// To use a custom generator, register it with Server.register_generator
// first, then reference it by name here.
@[params]
pub struct WorldConfig {
pub:
	name           string
	dimension      world.Dimension = world.overworld
	generator_name string
}

// load_world returns the loaded world, loading it from storage or creating
// it when necessary. Repeated calls for the same world return the existing
// handle.
//
// The underlying world lifecycle remains owned by Hub.
pub fn (mut s Server) load_world(config WorldConfig) !session.World {
	if handle := s.hub.world_handle(config.name) {
		return handle
	}
	factory := s.hub.world_factory or { return error('world factory not configured') }
	if factory.exists(config.name) {
		s.hub.load_world(config.name)!
	} else {
		s.hub.create_world(config.name, config.dimension, config.generator_name)!
	}
	return s.hub.world_handle(config.name) or {
		error('world "${config.name}" failed to register after loading')
	}
}

// world returns the named world's public handle or an error if no world
// by that name is currently loaded.
pub fn (mut s Server) world(name string) !session.World {
	return s.hub.world_handle(name) or { error('world "${name}" is not loaded') }
}

// worlds returns a handle for every currently loaded world.
pub fn (mut s Server) worlds() []session.World {
	names := s.hub.list_worlds()
	mut out := []session.World{cap: names.len}
	for name in names {
		if handle := s.hub.world_handle(name) {
			out << handle
		}
	}
	return out
}

// unload_world stops and releases a loaded world without deleting its
// stored data. It refuses to unload the default world or a world that still
// contains players; callers must move or disconnect them first.
pub fn (mut s Server) unload_world(name string) ! {
	s.hub.unload_world(name)!
}

pub fn (mut s Server) register_generator(name string, factory fn (dim world.Dimension) world.Generator) {
	s.hub.register_generator(name, factory)
}
