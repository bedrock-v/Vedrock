module event

// PlayerView is the narrow slice of a session exposed to event handlers, not
// the player itself. It is just a view onto one. It lets handlers identify and
// message the player without event importing session.
pub interface PlayerView {
	name() string
mut:
	send_message(message string) !
}
