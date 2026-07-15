// Module light is a server-side light-LEVEL engine (block light + sky light).
//
// IMPORTANT - Bedrock rendering light is CLIENT-side. In Minecraft: Bedrock
// Edition the client computes block/sky light for rendering itself, and the
// server does NOT send light in the chunk packet (see server/world/chunk.v
// serialize() - no light data, deliberately). So this engine is NOT needed for
// the client to render light.
//
// Its only purpose is future GAMEPLAY logic that has to know the light level at
// a position - mob-spawn eligibility, crop/tree growth, phantom spawning, etc.
// Vedrock has no such consumer yet, so this module is self-contained,
// unit-tested infrastructure that a gameplay system can query later. It is
// deliberately NOT wired into the chunk network packet.
//
// The propagation model mirrors the inspiration engines (dragonfly
// server/world/chunk/light*.go and PocketMine-MP src/world/light/): light
// spreads by a breadth-first flood fill, losing 1 level per block travelled and
// being attenuated/blocked by the opacity of the block it enters.
module light

// max_light is the brightest a light level can be, matching vanilla's 0-15.
pub const max_light = u8(15)

// BlockSource reads abstract block ids from a world by absolute coordinates.
// The engine talks only to this interface so it never imports session/world/
// block internals and stays unit-testable against an in-memory grid. The ids it
// returns are looked up in this module's local emission/opacity table - see
// air, glowstone and friends below. Hub (or a chunk view) can satisfy this later
// by mapping its own block ids onto these constants.
pub interface BlockSource {
	get_block(x int, y int, z int) int
}

// max_volume caps how many blocks a single light computation may touch so a huge
// region query cannot allocate unbounded memory. 128^3 = ~2M blocks, one u8 per
// block per light type, so a full block+sky computation over the cap costs about
// 4 MB of light storage plus the source grid. Callers that need more must tile.
pub const max_volume = 128 * 128 * 128

// Known block ids. This is a LOCAL, self-contained table - it does not touch the
// Block interface or server/block/*.v. The ids are arbitrary but stable within
// this module; a real BlockSource maps its own blocks onto these. It is a
// starting set meant to be extended as gameplay needs more blocks.
pub const air = 0
pub const stone = 1 // stand-in for any fully opaque, non-emitting block
pub const water = 2 // transparent but attenuates light beyond the normal falloff
pub const leaves = 3 // same idea as water - diffuses without fully blocking
pub const glowstone = 100
pub const sea_lantern = 101
pub const lava = 102
pub const torch = 103
pub const jack_o_lantern = 104
pub const redstone_torch = 105
pub const beacon = 106

// emission returns the block-light level a block id emits, 0-15. Only the known
// emitters glow - everything else is dark. Extend this table as needed.
pub fn emission(block_id int) u8 {
	return match block_id {
		glowstone { u8(15) }
		sea_lantern { u8(15) }
		lava { u8(15) }
		beacon { u8(15) }
		jack_o_lantern { u8(15) }
		torch { u8(14) }
		redstone_torch { u8(7) }
		else { u8(0) }
	}
}

// filter returns how many extra light levels a block id removes from light that
// passes THROUGH it, on top of the base 1-per-block falloff. 0 means fully
// transparent (light only loses the normal 1 level), max_light means fully
// opaque (light cannot pass at all). Water and leaves diffuse light - they let
// it through but eat a couple of extra levels. Unknown non-air ids are treated
// as opaque so the engine errs on the side of blocking, like a solid block.
pub fn filter(block_id int) u8 {
	return match block_id {
		air {
			u8(0)
		}
		water {
			u8(2)
		}
		leaves {
			u8(1)
		}
		// Emitters are transparent to travelling light - they only add their own.
		glowstone, sea_lantern, lava, torch, jack_o_lantern, redstone_torch, beacon {
			u8(0)
		}
		else {
			max_light
		} // stone and any unknown block fully block light
	}
}

// opaque reports whether a block fully blocks light (a filter of max_light).
// Sky light stops descending at 15 the moment it hits an opaque block.
pub fn opaque(block_id int) bool {
	return filter(block_id) >= max_light
}
