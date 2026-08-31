module cmd

import server.internal.language
import bedrock_v.protocol.current as proto

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
	// Heap in use and total heap reserved from the OS, both in bytes.
	memory_used_bytes             i64
	memory_heap_bytes             i64
	args                          []string
	active_chunk_generation_count i64
	chunk_cache_entries           i64
	chunk_cache_bytes             i64
}

pub interface Command {
	name() string
	description() string
	aliases() []string
	// permission returns the permission node required to run this command
	// or '' if it needs none (public to everyone).
	permission() string
	// arguments describes this command's expected syntax; Registry.dispatch
	// validates raw tokens against it before execute runs and available_commands() uses it to
	// build real client autocomplete data.
	arguments() []Argument
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
	return Registry{}
}

pub fn (mut r Registry) register(cmd Command) {
	// Keys are stored lower-cased so unregister and resolve (which both
	// lower-case) agree - otherwise a command with any uppercase in its name
	// could never be disabled via permissions.yml.
	key := cmd.name().to_lower()
	r.commands[key] = cmd
	for alias in cmd.aliases() {
		r.aliases[alias.to_lower()] = key
	}
}

// unregister removes a previously registered command
// (and any aliases pointing to it) by name.
pub fn (mut r Registry) unregister(name string) {
	key := name.to_lower()
	if key !in r.commands {
		return
	}
	r.commands.delete(key)
	mut stale_aliases := []string{}
	for alias, target in r.aliases {
		if target == key {
			stale_aliases << alias
		}
	}
	for alias in stale_aliases {
		r.aliases.delete(alias)
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
		sender.send_message(ctx_base.lang.t('cmd.empty'))!
		return
	}
	parts := trimmed.split(' ')
	name := parts[0]
	args := parts[1..].clone()
	cmd := r.resolve(name) or {
		sender.send_message(ctx_base.lang.tf('cmd.unknown', {
			'Name': name
		}))!
		return
	}
	if !visible(cmd, sender) {
		sender.send_message(ctx_base.lang.t('cmd.no_permission'))!
		return
	}
	if !validate_arguments(cmd.arguments(), args) {
		sender.send_message(usage_line(cmd))!
		return
	}
	ctx := Context{
		lang:              ctx_base.lang
		sender_name:       ctx_base.sender_name
		player_count:      ctx_base.player_count
		max_players:       ctx_base.max_players
		server_motd:       ctx_base.server_motd
		uptime_seconds:    ctx_base.uptime_seconds
		tps:               ctx_base.tps
		load:              ctx_base.load
		memory_used_bytes: ctx_base.memory_used_bytes
		memory_heap_bytes: ctx_base.memory_heap_bytes
		args:              args
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

// available_commands returns a pointer, like every other packet builder
// here. The packet gets queued and encoded later by a writer thread, so a
// value would leave the caller pointing at a stack variable that's gone
// by the time the writer runs.
pub fn (r &Registry) available_commands(sender Sender) &proto.AvailableCommandsPacket {
	mut pkt := &proto.AvailableCommandsPacket{}
	mut enum_value_index := map[string]u32{}
	for name, cmd in r.commands {
		if !visible(cmd, sender) {
			continue
		}
		mut parameters := []proto.ParameterDataEntry{}
		for a in cmd.arguments() {
			values := a.enum_values()
			type_info := if values.len > 0 {
				enum_index := pkt.enum_data.len
				mut value_indices := []u32{}
				for v in values {
					idx := enum_value_index[v] or {
						new_idx := u32(pkt.enum_values.len)
						pkt.enum_values << v
						enum_value_index[v] = new_idx
						new_idx
					}
					value_indices << idx
				}
				pkt.enum_data << proto.EnumDataEntry{
					name:   '${name}_${a.name()}'
					values: value_indices
				}
				arg_flag_enum | arg_flag_valid | u32(enum_index)
			} else {
				arg_flag_valid | a.network_type_info()
			}
			parameters << proto.ParameterDataEntry{
				name:         a.name()
				parse_symbol: type_info
				is_optional:  a.optional()
				options:      0
			}
		}
		pkt.commands << proto.CommandsEntry{
			name:                        name
			description:                 cmd.description()
			flags:                       0
			permission_level:            proto.CommandPermissionLevelString.any
			alias_enum:                  -1
			chained_sub_command_indices: []i32{}
			overloads:                   [
				proto.OverloadsEntry{
					is_chaining:    false
					parameter_data: parameters
				},
			]
		}
	}
	return pkt
}
