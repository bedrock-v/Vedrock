module permission

import os

pub const default_player_permissions_file = 'player_permissions.yml'

struct PlayerGrant {
	node  string
	value bool
}

pub struct PlayerGrants {
mut:
	by_key map[string][]PlayerGrant
}

pub fn load_player_grants(path string) !PlayerGrants {
	if !os.exists(path) {
		write_default_player_grants(path)!
		return PlayerGrants{}
	}
	content := os.read_file(path)!
	mut grants := PlayerGrants{}
	for raw_line in content.split_into_lines() {
		line := raw_line.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		// (e.g. "xuid:555: vedrock.cmd.status")
		idx := line.index(': ') or { continue }
		key := line[..idx].trim_space().to_lower()
		value := line[idx + 1..].trim_space()
		if key == '' || value == '' {
			continue
		}
		mut entries := []PlayerGrant{}
		for raw_node in value.split(',') {
			mut node := raw_node.trim_space()
			if node == '' {
				continue
			}
			mut granted := true
			if node.starts_with('-') {
				granted = false
				node = node[1..].trim_space()
			}
			if node != '' {
				entries << PlayerGrant{
					node:  node
					value: granted
				}
			}
		}
		if entries.len > 0 {
			grants.by_key[key] = entries
		}
	}
	return grants
}

pub fn (g &PlayerGrants) apply(mut p Permissible, name string, xuid string, uuid string) {
	for entry in g.by_key[name.to_lower()] {
		p.set_permission(entry.node, entry.value)
	}
	if xuid != '' {
		for entry in g.by_key['xuid:${xuid.to_lower()}'] {
			p.set_permission(entry.node, entry.value)
		}
	}
	if uuid != '' {
		for entry in g.by_key['uuid:${uuid.to_lower()}'] {
			p.set_permission(entry.node, entry.value)
		}
	}
}

fn write_default_player_grants(path string) ! {
	mut lines := []string{}
	lines << '# Vedrock per-player permission grants'
	lines << '# Applies on top of permissions.yml + ops.txt. use this to give (or take away)'
	lines << '#'
	lines << '# Format: <player-name | xuid:<xuid> | uuid:<uuid>>: <node>, -<node-to-deny>, ...'
	lines << '# A bare node grants it; a "-" prefix explicitly denies it. One line per player.'
	lines << '#'
	lines << '# Examples:'
	lines << '# Steve: vedrock.cmd.status, vedrock.cmd.gamemode.other'
	lines << '# xuid:2535413414841234: -vedrock.cmd.version'
	lines << '#'
	lines << '# Known permission nodes:'
	for perm in all() {
		if perm.description != '' {
			lines << '#   ${perm.name} - ${perm.description}'
		} else {
			lines << '#   ${perm.name}'
		}
	}
	os.write_file(path, lines.join('\n') + '\n')!
}
