module event

import server.cmd

// Every event carries the player it originated from as a cmd.Sender - the same
// interface commands use - so handlers can message, kick or query the player
// without the event package ever importing the session package. Coordinates and
// ids are plain primitives for the same reason.

// JoinData is dispatched right after a player finishes spawning. Cancelling it
// suppresses the broadcast join message; editing message changes it.
pub struct JoinData {
pub mut:
	player  cmd.Sender
	message string
}

// QuitData is dispatched when a spawned player leaves. Same rules as JoinData.
pub struct QuitData {
pub mut:
	player  cmd.Sender
	message string
}

// ChatData is dispatched for a public chat message. Cancelling it drops the
// message; editing message rewrites what everyone sees.
pub struct ChatData {
pub mut:
	player  cmd.Sender
	message string
}

// CommandData is dispatched before a player command runs. Cancelling it stops
// the command; editing command rewrites what is executed.
pub struct CommandData {
pub mut:
	player  cmd.Sender
	command string
}

// BlockBreakData is dispatched before a block is broken. block_id is the block
// being removed. Cancelling it leaves the block in place.
pub struct BlockBreakData {
pub:
	x        int
	y        int
	z        int
	block_id int
pub mut:
	player cmd.Sender
}

// BlockPlaceData is dispatched before a block is placed. block_id is the block
// being placed. Cancelling it stops the placement.
pub struct BlockPlaceData {
pub:
	x        int
	y        int
	z        int
	block_id int
pub mut:
	player cmd.Sender
}

// InteractData is dispatched when a player right-clicks a block, before any
// placement is decided. Useful for lobby signs and NPC-style interactions.
// Cancelling it stops the interaction (and any place that would follow).
pub struct InteractData {
pub:
	x    int
	y    int
	z    int
	face int
pub mut:
	player cmd.Sender
}

// AttackData is dispatched when a player attacks an entity. player is the
// attacker, victim_runtime_id the target. Editing damage changes the hit;
// cancelling it deals no damage and no knockback.
pub struct AttackData {
pub:
	victim_runtime_id u64
	critical          bool
pub mut:
	player cmd.Sender
	damage f32
}

// HurtData is dispatched when a player takes damage. player is the victim,
// attacker_name the source. Editing amount changes the damage; cancelling it
// negates the damage entirely.
pub struct HurtData {
pub:
	attacker_name string
pub mut:
	player cmd.Sender
	amount f32
}

// DeathData is dispatched when a player dies. message_key/params are the death
// broadcast; cancelling it suppresses the broadcast, editing message_key
// rewrites it.
pub struct DeathData {
pub:
	params []string
pub mut:
	player      cmd.Sender
	message_key string
}

// RespawnData is dispatched before a player respawns. Handlers may move the
// respawn point by editing x/y/z (e.g. to send players back to a lobby).
pub struct RespawnData {
pub mut:
	player cmd.Sender
	x      f32
	y      f32
	z      f32
}

// MoveData is dispatched when a player moves. Editing x/y/z is ignored; cancel
// rejects the movement and snaps the player back to where they were.
pub struct MoveData {
pub:
	x f32
	y f32
	z f32
pub mut:
	player cmd.Sender
}

// GameModeChangeData is dispatched before a player's gamemode changes. Editing
// mode changes the target gamemode; cancelling it keeps the current one.
pub struct GameModeChangeData {
pub mut:
	player cmd.Sender
	mode   int
}
