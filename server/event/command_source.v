module event

// CommandSource is whoever asked the server to do something: a connected
// player or the console. It carries only what a lower layer needs from them:
// who they are and how to answer them, because the console is a valid source
// and is not a player.
//
// It lives here rather than in player because the console is not a player and
// because cmd imports player, so player cannot name a type declared in cmd.
// player.Player deliberately doesn't satisfy it either: Player's verbs take the
// world transaction that proves they run on the owning actor, and a source is
// reached from the session thread, where there is no transaction yet. What a
// command may do to a player is cmd.Sender which embeds this and adds the rest.
pub interface CommandSource {
	name() string
	is_player() bool
mut:
	send_message(message string) !
	send_translation(key string, parameters []string) !
}
