module db

import os
import server.world

const meta_filename = 'meta.txt'

// WorldMeta is a world's persisted identity which generator built it and
// which dimension it belongs to. Restoring these correctly on load is the
// whole point of this file: without it, a reloaded nether/end world would
// silently come back as an overworld-shaped world instead.
struct WorldMeta {
	generator string
	dimension int
}

// write_world_meta persists generator/dim next to a world's LevelDB folders.
// Called once, at creation time.
fn write_world_meta(dir string, generator string, dim world.Dimension) ! {
	content := 'generator: ${generator}\ndimension: ${dim.id}\n'
	os.write_file(os.join_path(dir, meta_filename), content)!
}

// read_world_meta reads a previously written meta file or none if the world
// predates metadata persistence. Callers fall back to their own defaults in
// that case, so an existing world keeps loading exactly as it did before.
fn read_world_meta(dir string) ?WorldMeta {
	content := os.read_file(os.join_path(dir, meta_filename)) or { return none }
	mut generator := ''
	mut dimension := 0
	for raw_line in content.split_into_lines() {
		line := raw_line.trim_space()
		idx := line.index(': ') or { continue }
		key := line[..idx].trim_space()
		value := line[idx + 2..].trim_space()
		match key {
			'generator' { generator = value }
			'dimension' { dimension = value.int() }
			else {}
		}
	}
	if generator == '' {
		return none
	}
	return WorldMeta{
		generator: generator
		dimension: dimension
	}
}
