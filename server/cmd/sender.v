module cmd

// Sender is the live connection that issued a cmd. Context carries
// read-only stats for building output; anything a Command needs to send
// back or mutate goes through Sender instead.
pub interface Sender {
	has_permission(name string) bool
	name() string
	whitelist_enabled() bool
	whitelist_names() []stringW
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
}
