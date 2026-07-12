module db

import os

// load_named opens the world stored under worlds_dir/name and pulls its
// overrides into memory.
pub fn load_named(worlds_dir string, name string, generator_name string) !&World {
	path := os.join_path(worlds_dir, name, 'db')
	store := open_world(path)!
	mut w := new_world(name, store, generator_name)
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
