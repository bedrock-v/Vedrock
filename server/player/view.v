module player

import bedrock_v.protocol.types
import server.form
import server.player.bossbar
import server.player.scoreboard
import server.player.title

// View is the narrow, capability-only contract for "acts like a player":
// identity, permission, messaging, movement, inventory, UI, etc. It exists so
// lower layers (event and later entity for AI targeting) can reference a
// player without importing session and without each one re deriving its own
// slice of what a player is.
pub interface View {
	name() string
	has_permission(name string) bool
	is_player() bool
mut:
	send_message(message string) !
	send_translation(key string, parameters []string) !
	set_gamemode(mode Gamemode)
	kill()
	disconnect(message string)
	position() types.Vector3
	teleport(x f32, y f32, z f32)
	clear_inventory()
	give_item(id string, count int) bool
	send_form(f form.Form) !
	send_scoreboard(board &scoreboard.Scoreboard)
	remove_scoreboard()
	send_title(t title.Title)
	send_bossbar(bar bossbar.BossBar)
	remove_bossbar()
}
