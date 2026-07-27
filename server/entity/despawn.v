module entity

// DespawnPolicy configures how an entity despawns naturally once players
// are far away, mirroring Bedrock's minecraft:despawn component: distance,
// random chance, inactivity and simulation-distance edge can each be
// switched on per entity type. The zero value turns everything off.
//
// random_chance and inactivity only take effect once distance is also on -
// they refine the distance rule rather than triggering independently.
// simulation_edge isn't implemented yet.
pub struct DespawnPolicy {
pub:
	distance        bool
	random_chance   bool
	inactivity      bool
	simulation_edge bool

	min_distance         f32 = 32.0
	max_distance         f32 = 128.0
	random_chance_one_in i64 = 800
	inactivity_ticks     i64 = 600
}

pub const natural_mob_despawn_policy = DespawnPolicy{
	distance:        true
	random_chance:   true
	inactivity:      true
	simulation_edge: true
}
