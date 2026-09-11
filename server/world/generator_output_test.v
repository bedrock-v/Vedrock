module world

import hash.fnv1a

// A chunk nobody has edited is generated again every time its world loads, so
// changing what a generator produces changes every existing world wherever
// nothing has been built. These digests pin that output: one changes only when
// the terrain is meant to.

const pinned_chunks = [[0, 0], [1, -1], [-3, 2], [5, -7], [-20, 13], [40, 40]]

// block_at builds its answer apart from generate, so it is pinned separately.
const pinned_columns = [[0, 0], [7, -3], [-45, 18], [130, -260]]

fn chunk_digest(g Generator, dim Dimension) u64 {
	mut bytes := []u8{}
	for pos in pinned_chunks {
		c := g.generate(pos[0], pos[1])
		for x in 0 .. 16 {
			for z in 0 .. 16 {
				push_int(mut bytes, c.biome_id(x, z))
				for y in dim.min_y .. dim.max_y() + 1 {
					push_int(mut bytes, c.block_id(x, y, z))
				}
			}
		}
	}
	return fnv1a.sum64(bytes)
}

fn column_digest(g Generator, dim Dimension) u64 {
	mut bytes := []u8{}
	for pos in pinned_columns {
		push_int(mut bytes, g.biome_at(pos[0], pos[1]))
		for y in dim.min_y .. dim.max_y() + 1 {
			push_int(mut bytes, g.block_at(pos[0], y, pos[1]))
		}
	}
	push_int(mut bytes, g.spawn_point().y)
	return fnv1a.sum64(bytes)
}

fn push_int(mut bytes []u8, v int) {
	bytes << u8(v)
	bytes << u8(v >> 8)
	bytes << u8(v >> 16)
	bytes << u8(v >> 24)
}

fn test_normal_generator_output_is_pinned() {
	g := NormalGenerator{}
	assert chunk_digest(g, overworld) == u64(11255914008902663412)
	assert column_digest(g, overworld) == u64(18238884470794750234)
	origin := g.spawn_point()
	assert origin.x == 0 && origin.z == 0
}

fn test_nether_generator_output_is_pinned() {
	g := NetherGenerator{}
	assert chunk_digest(g, nether) == u64(10942659346042275470)
	assert column_digest(g, nether) == u64(18239548844026247721)
}

fn test_end_generator_output_is_pinned() {
	g := EndGenerator{}
	assert chunk_digest(g, the_end) == u64(6133541026081350682)
	assert column_digest(g, the_end) == u64(10002370967586145064)
}

// A seed has to reach both ways a generator answers. If it reached only one,
// the chunks sent to players and single block lookups would describe two
// different worlds.
fn test_a_seed_changes_both_generate_and_block_at() {
	for seed in [i64(42), -9_000_000_000] {
		normal := NormalGenerator{
			seed: seed
		}
		assert chunk_digest(normal, overworld) != u64(11255914008902663412)
		assert column_digest(normal, overworld) != u64(18238884470794750234)
		nether_gen := NetherGenerator{
			seed: seed
		}
		assert chunk_digest(nether_gen, nether) != u64(10942659346042275470)
		assert column_digest(nether_gen, nether) != u64(18239548844026247721)
		end_gen := EndGenerator{
			seed: seed
		}
		assert chunk_digest(end_gen, the_end) != u64(6133541026081350682)
		assert column_digest(end_gen, the_end) != u64(10002370967586145064)
	}
}

// 12158 and 16372 once folded to the same 32 bit mask and generated the same
// world. Every bit of a seed has to reach the terrain.
fn test_seeds_that_once_shared_a_mask_make_different_worlds() {
	assert chunk_digest(NormalGenerator{ seed: 12158 }, overworld) != chunk_digest(NormalGenerator{
		seed: 16372
	}, overworld)
	assert chunk_digest(NetherGenerator{ seed: 12158 }, nether) != chunk_digest(NetherGenerator{
		seed: 16372
	}, nether)
	assert chunk_digest(EndGenerator{ seed: 12158 }, the_end) != chunk_digest(EndGenerator{
		seed: 16372
	}, the_end)
}
