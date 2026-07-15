module cmd

import server.form

// Sender is the live connection that issued a cmd. Context carries
// read-only stats for building output; anything a Command needs to send
// back or mutate goes through Sender instead.
pub interface Sender {
	has_permission(name string) bool
	name() string
	whitelist_enabled() bool
	whitelist_names() []string
	is_player() bool
mut:
	send_message(message string) !
	send_translation(key string, parameters []string) !
	set_gamemode(mode int)
	find_player(name string) ?Sender
	set_operator(value bool)
	kill()
	position() (f32, f32, f32)
	teleport(x f32, y f32, z f32)
	// place_water sets a water source at the block position and starts its spread.
	place_water(x int, y int, z int)
	clear_inventory()
	give_item(id string, count int) bool
	whitelist_add(name string)
	whitelist_remove(name string)
	whitelist_set_enabled(value bool)
	set_difficulty(value int)
	broadcast_message(text string)
	// show_title sends a title/subtitle/actionbar to this sender only.
	show_title(kind int, text string)
	// broadcast_title sends to every connected player (for /title @a).
	broadcast_title(kind int, text string)
	// show_scoreboard displays a sidebar scoreboard to this sender with the
	// given title and lines rendered top-to-bottom.
	show_scoreboard(title string, lines []string)
	// clear_scoreboard removes the sidebar scoreboard from this sender.
	clear_scoreboard()
	send_form(f form.Form) !
	// world management. Mutating ops return an error the command relays to the
	// sender; list/info are read-only snapshots.
	world_names() []string
	world_info(name string) ?WorldSummary
	world_create(name string) !
	world_delete(name string) !
	world_teleport(name string) !
}

// WorldSummary is a read-only snapshot of a loaded world, built for command
// output so the cmd layer never depends on the db types directly.
pub struct WorldSummary {
pub:
	name       string
	generator  string
	overrides  int
	is_default bool
	players    int
}
