module world

pub const biome_ocean = 0
pub const biome_desert = 2
pub const biome_taiga = 5
pub const biome_hell = 8
pub const biome_the_end = 9
pub const biome_snowy_taiga = 30

pub fn default_biome_for(dim Dimension) int {
	return match dim.id {
		1 { biome_hell }
		2 { biome_the_end }
		else { plains_biome_id }
	}
}
