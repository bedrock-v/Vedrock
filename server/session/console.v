module session

import bedrock_v.protocol.types
import server.internal.logger
import server.cmd
import server.form
import server.player
import server.player.scoreboard

// ConsoleSender adapts the server console to the cmd.Sender interface.
// It has every permission and writes command output to the server log.
@[heap]
pub struct ConsoleSender {
mut:
	hub &Hub
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn new_console_sender(mut hub Hub, log &logger.Logger) &ConsoleSender {
	return &ConsoleSender{
		hub: hub
		log: log
	}
}

fn (c &ConsoleSender) has_permission(_ string) bool {
	return true
}

pub fn (c &ConsoleSender) name() string {
	return 'CONSOLE'
}

fn (c &ConsoleSender) is_player() bool {
	return false
}

fn (mut c ConsoleSender) send_message(message string) ! {
	c.log.info(strip_formatting(message))
}

fn (mut c ConsoleSender) send_translation(key string, parameters []string) ! {
	// The console has no client-side translation table, so log the raw key
	// with its parameters instead.
	if parameters.len == 0 {
		c.log.info(key)
		return
	}
	c.log.info('${key} [${parameters.join(', ')}]')
}

fn (mut c ConsoleSender) set_gamemode(_ player.Gamemode) {
	// The console is not an in-world player; nothing to update.
}

fn (mut c ConsoleSender) find_player(name string) ?cmd.Sender {
	target := c.hub.session_by_name(name) or { return none }
	return target
}

// The console itself is never a valid target for these (find_player never
// resolves to a ConsoleSender) but every Sender must implement the full
// interface.
fn (mut c ConsoleSender) set_operator(_ bool) {}

fn (mut c ConsoleSender) kill() {}

fn (mut c ConsoleSender) disconnect(_ string) {}

fn (mut c ConsoleSender) position() types.Vector3 {
	return types.Vector3{}
}

fn (mut c ConsoleSender) teleport(_ f32, _ f32, _ f32) {}

fn (mut c ConsoleSender) place_water(x int, y int, z int) {
	c.hub.place_water(x, y, z)
}

fn (mut c ConsoleSender) clear_inventory() {}

fn (mut c ConsoleSender) give_item(_ string, _ int) bool {
	return false
}

fn (mut c ConsoleSender) send_form(_ form.Form) ! {
	return error('the console cannot display forms')
}

fn (mut c ConsoleSender) send_scoreboard(_ &scoreboard.Scoreboard) {
	// The console has no client to render a scoreboard on.
}

fn (mut c ConsoleSender) remove_scoreboard() {}

// strip_formatting removes Minecraft § formatting codes so command output
// stays readable in a terminal.
fn strip_formatting(message string) string {
	runes := message.runes()
	mut out := []rune{cap: runes.len}
	mut i := 0
	for i < runes.len {
		if runes[i] == `§` && i + 1 < runes.len {
			i += 2
			continue
		}
		out << runes[i]
		i++
	}
	return out.string()
}
