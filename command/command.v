module command

import protocol
import language

pub struct Context {
pub:
	lang           &language.Lang = unsafe { nil }
	sender_name    string
	player_count   int
	max_players    int
	server_motd    string
	uptime_seconds i64
	tps            f64
	load           f64
	args           []string
}

pub interface Command {
	name() string
	description() string
	aliases() []string
	// permission returns the permission node required to run this command
	// or '' if it needs none (public to everyone).
	permission() string
	execute(mut sender Sender, ctx Context) !
}

// visible reports whether sender is allowed to see/run cmd.
pub fn visible(cmd Command, sender Sender) bool {
	perm := cmd.permission()
	return perm == '' || sender.has_permission(perm)
}

pub struct Registry {
pub mut:
	commands map[string]Command
	aliases  map[string]string
}

pub fn new_registry() Registry {
	mut r := Registry{}
	r.register(VersionCommand{})
	r.register(StatusCommand{})
	r.register(GamemodeCommand{})
	return r
}

pub fn (mut r Registry) register(cmd Command) {
	r.commands[cmd.name()] = cmd
	for alias in cmd.aliases() {
		r.aliases[alias] = cmd.name()
	}
}

pub fn (r &Registry) resolve(name string) ?Command {
	key := name.to_lower()
	if key in r.commands {
		return r.commands[key]
	}
	if key in r.aliases {
		return r.commands[r.aliases[key]]
	}
	return none
}

pub fn (r &Registry) dispatch(line string, mut sender Sender, ctx_base Context) ! {
	trimmed := line.trim_left('/').trim_space()
	if trimmed == '' {
		sender.send_message(ctx_base.lang.t('command.empty'))!
		return
	}
	parts := trimmed.split(' ')
	name := parts[0]
	args := parts[1..].clone()
	cmd := r.resolve(name) or {
		sender.send_message(ctx_base.lang.tf('command.unknown', {
			'Name': name
		}))!
		return
	}
	if !visible(cmd, sender) {
		sender.send_message(ctx_base.lang.t('command.no_permission'))!
		return
	}
	ctx := Context{
		lang:           ctx_base.lang
		sender_name:    ctx_base.sender_name
		player_count:   ctx_base.player_count
		max_players:    ctx_base.max_players
		server_motd:    ctx_base.server_motd
		uptime_seconds: ctx_base.uptime_seconds
		tps:            ctx_base.tps
		load:           ctx_base.load
		args:           args
	}
	cmd.execute(mut sender, ctx)!
}

pub fn (r &Registry) names() []string {
	mut out := []string{}
	for name, _ in r.commands {
		out << name
	}
	return out
}

pub fn (r &Registry) available_commands(sender Sender) protocol.AvailableCommandsPacket {
	mut commands := []protocol.CommandData{}
	for name, cmd in r.commands {
		if !visible(cmd, sender) {
			continue
		}
		commands << protocol.CommandData{
			name:             name
			description:      cmd.description()
			flags:            0
			permission:       'any'
			alias_enum_index: -1
			overloads:        [
				protocol.CommandOverload{
					chaining:   false
					parameters: []protocol.CommandParameter{}
				},
			]
		}
	}
	return protocol.AvailableCommandsPacket{
		commands: commands
	}
}
