module event

// Every event carries the player it originated from as a PlayerView (see
// player.v) so handlers can identify and message them without the event
// package ever importing the session package. Coordinates and ids are plain
// primitives for the same reason.

// JoinData is dispatched right after a player finishes spawning. Cancelling it
// suppresses the broadcast join message; editing message changes it.
pub struct JoinData {
pub mut:
	player  PlayerView
	message string
}

// QuitData is dispatched when a spawned player leaves. Same rules as JoinData.
pub struct QuitData {
pub mut:
	player  PlayerView
	message string
}

// ChatData is dispatched for a public chat message. Cancelling it drops the
// message; editing message rewrites what everyone sees.
pub struct ChatData {
pub mut:
	player  PlayerView
	message string
}

// CommandData is dispatched before a player command runs. Cancelling it stops
// the command; editing command rewrites what is executed.
pub struct CommandData {
pub mut:
	player  PlayerView
	command string
}

// MoveData is dispatched when a player moves. Editing x/y/z is ignored; cancel
// rejects the movement and snaps the player back to where they were.
pub struct MoveData {
pub:
	x f32
	y f32
	z f32
pub mut:
	player PlayerView
}

// GameModeChangeData is dispatched before a player's gamemode changes. Editing
// mode changes the target gamemode; cancelling it keeps the current one.
pub struct GameModeChangeData {
pub mut:
	player PlayerView
	mode   int
}
