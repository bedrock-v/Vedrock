module db

import server.world

// Factory creates, opens, lists and deletes named world backends. Hub only
// ever talks to worlds through this interface (plus the Provider/World it
// hands back). Swap it for something other than LevelDBFactory to back
// worlds with an entirely different storage mechanism.
pub interface Factory {
	exists(name string) bool
	discover() []string
mut:
	create(name string, dim world.Dimension, generator string) !Provider
	// open loads a persisted world, resolving its own generator/dimension
	// from whatever metadata the backend keeps (falling back to
	// fallback_generator/fallback_dim if it can't). Returns a fully loaded
	// World, not just a raw Provider, so a caller never has to reread
	// overrides a second time.
	open(name string, fallback_generator string, fallback_dim world.Dimension) !&World
	delete(name string) !
}

// LevelDBFactory is Vedrock's own default, one LevelDB-backed folder per
// world under worlds_dir. It is a thin Factory shaped face over the existing
// manage.v/world_loader.v functions, not a reimplementation of them.
pub struct LevelDBFactory {
pub:
	worlds_dir string
}

pub fn (f LevelDBFactory) exists(name string) bool {
	return world_exists(f.worlds_dir, name)
}

pub fn (f LevelDBFactory) create(name string, dim world.Dimension, generator string) !Provider {
	return create_world_store(f.worlds_dir, name, dim, generator)!
}

pub fn (f LevelDBFactory) open(name string, fallback_generator string, fallback_dim world.Dimension) !&World {
	return load_named(f.worlds_dir, name, fallback_generator, fallback_dim)!
}

pub fn (f LevelDBFactory) discover() []string {
	return discover_worlds(f.worlds_dir)
}

pub fn (f LevelDBFactory) delete(name string) ! {
	delete_world_files(f.worlds_dir, name)!
}
