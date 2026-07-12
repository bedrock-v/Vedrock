module session

import server.internal.logger
import server.cmd
import server.form

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

pub fn (c &ConsoleSender) has_permission(name string) bool {
	return true
}

pub fn (c &ConsoleSender) name() string {
	return 'CONSOLE'
}

pub fn (c &ConsoleSender) is_player() bool {
	return false
}

pub fn (mut c ConsoleSender) send_message(message string) ! {
	c.log.info(strip_formatting(message))
}

pub fn (mut c ConsoleSender) send_translation(key string, parameters []string) ! {
	// The console has no client-side translation table, so log the raw key
	// with its parameters instead.
	if parameters.len == 0 {
		c.log.info(key)
		return
	}
	c.log.info('${key} [${parameters.join(', ')}]')
}

pub fn (mut c ConsoleSender) set_gamemode(mode int) {
	// The console is not an in-world player; nothing to update.
}

pub fn (mut c ConsoleSender) find_player(name string) ?cmd.Sender {
	target := c.hub.session_by_name(name) or { return none }
	return target
}

// The console itself is never a valid target for these (find_player never
// resolves to a ConsoleSender) but every Sender must implement the full
// interface.
pub fn (mut c ConsoleSender) set_operator(value bool) {}

pub fn (mut c ConsoleSender) kill() {}

pub fn (mut c ConsoleSender) position() (f32, f32, f32) {
	return 0.0, 0.0, 0.0
}

pub fn (mut c ConsoleSender) teleport(x f32, y f32, z f32) {}

pub fn (mut c ConsoleSender) clear_inventory() {}

pub fn (mut c ConsoleSender) give_item(id string, count int) bool {
	return false
}

pub fn (mut c ConsoleSender) send_form(f form.Form) ! {
	return error('the console cannot display forms')
}

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
