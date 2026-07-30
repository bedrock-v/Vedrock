module event

// EntitySpawnData is dispatched before a non player entity is spawned.
// Cancelling it stops the spawn entirely.
pub struct EntitySpawnData {
pub:
	identifier string
	x          f32
	y          f32
	z          f32
}

// EntityDespawnData is dispatched after a non player entity is removed from
// the world (died, expired or was otherwise despawned). Observational only,
// cancelling has no effect.
pub struct EntityDespawnData {
pub:
	identifier string
	x          f32
	y          f32
	z          f32
}
