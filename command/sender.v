module command

// Sender is the live connection that issued a command. Context carries
// read-only stats for building output; anything a Command needs to send
// back or mutate goes through Sender instead.
pub interface Sender {
	has_permission(name string) bool
mut:
	send_message(message string) !
	send_translation(key string, parameters []string) !
	set_gamemode(mode int)
	find_player(name string) ?Sender
}
