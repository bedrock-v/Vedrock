module event

import server.player

// AttackData is dispatched when a player attacks an entity. player is the
// attacker, victim_runtime_id the target. Editing damage changes the hit;
// cancelling it deals no damage and no knockback.
pub struct AttackData {
pub:
	victim_runtime_id u64
	critical          bool
pub mut:
	player player.View
	damage f32
}

// HurtData is dispatched when a player takes damage. player is the victim,
// attacker_name the source. Editing amount changes the damage; cancelling it
// negates the damage entirely.
pub struct HurtData {
pub:
	attacker_name string
pub mut:
	player player.View
	amount f32
}

// DeathData is dispatched when a player dies. message_key/params are the death
// broadcast; cancelling it suppresses the broadcast, editing message_key
// rewrites it.
pub struct DeathData {
pub:
	params []string
pub mut:
	player      player.View
	message_key string
}

// RespawnData is dispatched before a player respawns. Handlers may move the
// respawn point by editing x/y/z (e.g. to send players back to a lobby).
pub struct RespawnData {
pub mut:
	player player.View
	x      f32
	y      f32
	z      f32
}
