module cmd

import server.player

// Sender is the live connection that issued a cmd. Context carries
// read-only stats for building output; anything a Command needs to send
// back or mutate goes through Sender instead. Embeds player.View for the
// part that's genuinely about a specific player (identity, messaging,
// movement, inventory, UI, etc.) and adds only what's actually about running
// commands: whitelist/difficulty/broadcast/world management apply to the
// server, not to whichever player happens to be the sender.
pub interface Sender {
	player.View
	whitelist_enabled() bool
	whitelist_names() []string
mut:
	find_player(name string) ?Sender
	set_operator(value bool)
	// place_water sets a water source at the block position and starts its spread.
	place_water(x int, y int, z int)
	whitelist_add(name string)
	whitelist_remove(name string)
	whitelist_set_enabled(value bool)
	set_difficulty(value int)
	broadcast_message(text string)
	// show_title sends a title/subtitle/actionbar to this sender only.
	show_title(kind int, text string)
	// broadcast_title sends to every connected player (for /title @a).
	broadcast_title(kind int, text string)
	// world management. Mutating ops return an error the command relays to the
	// sender; list/info are read-only snapshots.
	world_names() []string
	world_info(name string) ?WorldSummary
	// world_create's dimension and generator are names rather than the
	// world.Dimension/world.Generator types themselves, so the cmd layer never
	// depends on the world package directly.
	world_create(name string, dimension string, generator string) !
	world_load(name string) !
	world_delete(name string) !
	world_teleport(name string) !
}

// WorldSummary is a read-only snapshot of a loaded world, built for command
// output so the cmd layer never depends on the db types directly.
pub struct WorldSummary {
pub:
	name       string
	generator  string
	dimension  string
	overrides  int
	is_default bool
	players    int
}
