module db

import os
import server.world

// world-lifecycle filesystem helpers. Anything that touches the on-disk world
// folder lives here so the safety checks (path traversal, staying inside
// worlds_dir) sit in one place.

// safe_world_dir resolves worlds_dir/name and refuses any name that would
// escape worlds_dir. Returns the absolute world folder path.
fn safe_world_dir(worlds_dir string, name string) !string {
	if name.trim_space() == '' {
		return error('world name is empty')
	}
	// Reject anything that could climb out of worlds_dir. A world is always a
	// single direct subdirectory, never a nested path.
	if name.contains('/') || name.contains('\\') || name.contains('..') || name == '.'
		|| os.is_abs_path(name) {
		return error('illegal world name "${name}"')
	}
	base := os.abs_path(worlds_dir)
	full := os.abs_path(os.join_path(worlds_dir, name))
	// Belt and suspenders - after normalisation the folder must still sit
	// directly under worlds_dir.
	if !full.starts_with(base + os.path_separator) {
		return error('world path escapes worlds directory')
	}
	return full
}

// world_exists reports whether a world folder with a db subdirectory is present
// under worlds_dir.
pub fn world_exists(worlds_dir string, name string) bool {
	full := safe_world_dir(worlds_dir, name) or { return false }
	return os.is_dir(os.join_path(full, 'db'))
}

// delete_world_files removes the on-disk folder for the named world. The caller
// is responsible for closing the LevelDB handle first - this only touches the
// filesystem. Refuses to delete anything outside worlds_dir or a world that
// isn't actually there.
pub fn delete_world_files(worlds_dir string, name string) ! {
	full := safe_world_dir(worlds_dir, name)!
	if !os.is_dir(full) {
		return error('world "${name}" does not exist on disk')
	}
	os.rmdir_all(full)!
}

// create_world_store creates a fresh, empty world on disk under worlds_dir and
// returns its opened store. Errors if a world by that name already exists.
pub fn create_world_store(worlds_dir string, name string, dim world.Dimension, generator string) !&WorldStore {
	full := safe_world_dir(worlds_dir, name)!
	if os.is_dir(full) {
		return error('world "${name}" already exists')
	}
	os.mkdir_all(full)!
	write_world_meta(full, generator, dim)!
	path := os.join_path(full, 'db')
	return open_world(path, dim)!
}
