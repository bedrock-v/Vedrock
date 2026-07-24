module db

import os
import server.world

// load_named opens the world stored under worlds_dir/name and pulls its
// overrides into memory.
pub fn load_named(worlds_dir string, name string, generator_name string, dim world.Dimension) !&World {
	full := os.join_path(worlds_dir, name)
	mut resolved_generator := generator_name
	mut resolved_dim := dim
	if meta := read_world_meta(full) {
		resolved_generator = meta.generator
		resolved_dim = world.dimension_by_id(meta.dimension) or { dim }
	}
	path := os.join_path(full, 'db')
	store := open_world(path, resolved_dim)!
	mut w := new_world(name, store, resolved_generator, resolved_dim)
	w.load()
	return w
}

// discover_worlds returns the names of every subdirectory under worlds_dir
// that looks like a world (has a db folder).
pub fn discover_worlds(worlds_dir string) []string {
	mut names := []string{}
	if !os.is_dir(worlds_dir) {
		return names
	}
	for entry in os.ls(worlds_dir) or { return names } {
		full := os.join_path(worlds_dir, entry)
		if os.is_dir(os.join_path(full, 'db')) {
			names << entry
		}
	}
	return names
}
