module command

pub struct Context {
pub:
	sender_name  string
	player_count int
	max_players  int
	server_motd  string
	args         []string
}

pub interface Command {
	name() string
	description() string
	aliases() []string
	execute(ctx Context) string
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

pub fn (r &Registry) dispatch(line string, ctx_base Context) string {
	trimmed := line.trim_left('/').trim_space()
	if trimmed == '' {
		return '§cEmpty command'
	}
	parts := trimmed.split(' ')
	name := parts[0]
	args := parts[1..].clone()
	cmd := r.resolve(name) or { return '§cUnknown command: ${name}' }
	ctx := Context{
		sender_name:  ctx_base.sender_name
		player_count: ctx_base.player_count
		max_players:  ctx_base.max_players
		server_motd:  ctx_base.server_motd
		args:         args
	}
	return cmd.execute(ctx)
}

pub fn (r &Registry) names() []string {
	mut out := []string{}
	for name, _ in r.commands {
		out << name
	}
	return out
}
