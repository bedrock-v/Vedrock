module db

import os
import strconv
import server.world

const meta_filename = 'meta.txt'

// WorldMeta is a world's persisted identity: which generator built it, which
// dimension it belongs to and the seed that generator was given.
// world instead.
struct WorldMeta {
	generator string
	dimension int
	seed      i64
}

// NoWorldMeta is a world with no meta file, one made before metadata was
// persisted. Callers fall back to their own defaults and seed 0, so such a
// world keeps loading exactly as it did before.
struct NoWorldMeta {
	Error
}

fn (e NoWorldMeta) msg() string {
	return 'the world has no ${meta_filename}'
}

// write_world_meta persists generator/dim/seed next to a world's LevelDB
// folders. Called once at creation time.
fn write_world_meta(dir string, generator string, dim world.Dimension, seed i64) ! {
	content := 'generator: ${generator}\ndimension: ${dim.id}\nseed: ${seed}\n'
	os.write_file(os.join_path(dir, meta_filename), content)!
}

// read_world_meta reads a previously written meta file. A file without a seed
// line was written before seeds existed and means seed 0, the terrain that
// world was always generated with.
fn read_world_meta(dir string) !WorldMeta {
	content := os.read_file(os.join_path(dir, meta_filename)) or { return NoWorldMeta{} }
	mut generator := ''
	mut dimension := 0
	mut seed := i64(0)
	for raw_line in content.split_into_lines() {
		line := raw_line.trim_space()
		idx := line.index(': ') or { continue }
		key := line[..idx].trim_space()
		value := line[idx + 2..].trim_space()
		match key {
			'generator' {
				generator = value
			}
			'dimension' {
				dimension = value.int()
			}
			'seed' {
				seed = strconv.parse_int(value, 10, 64) or {
					return error('${meta_filename} in ${dir} has a seed that is not a number: "${value}"')
				}
			}
			else {}
		}
	}
	if generator == '' {
		return NoWorldMeta{}
	}
	return WorldMeta{
		generator: generator
		dimension: dimension
		seed:      seed
	}
}
