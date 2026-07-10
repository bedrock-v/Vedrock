module permission

import os

pub const default_permissions_file = 'permissions.yml'

pub struct PermissionsConfig {
pub:
	disabled_commands []string
}

pub fn load_permissions_config(path string) !PermissionsConfig {
	if !os.exists(path) {
		write_default_permissions_config(path)!
		return PermissionsConfig{}
	}
	content := os.read_file(path)!
	mut disabled := []string{}
	for raw_line in content.split_into_lines() {
		line := raw_line.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		idx := line.index(':') or { continue }
		key := line[..idx].trim_space()
		value := line[idx + 1..].trim_space()
		if key == 'disabled-commands' {
			if value == '' {
				continue
			}
			for raw_name in value.split(',') {
				name := raw_name.trim_space().to_lower()
				if name != '' {
					disabled << name
				}
			}
			continue
		}
		default_value := parse_default_value(value) or { continue }
		set_default(key, default_value)
	}
	return PermissionsConfig{
		disabled_commands: disabled
	}
}

fn parse_default_value(s string) ?DefaultValue {
	return match s.to_lower() {
		'granted' { .granted }
		'denied' { .denied }
		'op' { .op }
		'not_op', 'not-op' { .not_op }
		else { none }
	}
}

fn write_default_permissions_config(path string) ! {
	mut lines := []string{}
	lines << '# Vedrock permissions configuration'
	lines << "# Override the default access level for any permission node below."
	lines << '# Edit it and restart to change who can use a command.'
	lines << '# Values: granted (everyone) | denied (nobody, unless granted per-player in-game) | op (operators only) | not_op (everyone except operators)'
	lines << ''
	for perm in all() {
		if perm.description != '' {
			lines << '# ${perm.description}'
		}
		lines << '${perm.name}: ${perm.default}'
		lines << ''
	}
	lines << '# Comma-separated default command names to disable entirely (unregistered on startup).'
	lines << 'disabled-commands: '
	os.write_file(path, lines.join('\n') + '\n')!
}
