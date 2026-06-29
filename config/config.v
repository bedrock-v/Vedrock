module config

import os

pub struct Config {
pub mut:
	motd                  string = 'Vedrock Server'
	sub_motd              string = 'A V Bedrock server'
	address               string = '0.0.0.0'
	port                  int    = 19132
	max_players           int    = 20
	view_distance         int    = 8
	gamemode              string = 'survival'
	xbox_auth             bool   = true
	compression_threshold int    = 256
	generator             string = 'flat'
	language              string = 'en'
	debug                 bool
}

const default_file = 'vedrock.yml'

pub fn load() !Config {
	return load_from(default_file)
}

pub fn load_from(path string) !Config {
	if !os.exists(path) {
		cfg := Config{}
		write_default(path, cfg)!
		return cfg
	}
	content := os.read_file(path)!
	mut cfg := Config{}
	values := parse_flat_yaml(content)
	cfg.motd = values['motd'] or { cfg.motd }
	cfg.sub_motd = values['sub-motd'] or { cfg.sub_motd }
	cfg.address = values['address'] or { cfg.address }
	cfg.port = (values['port'] or { cfg.port.str() }).int()
	cfg.max_players = (values['max-players'] or { cfg.max_players.str() }).int()
	cfg.view_distance = (values['view-distance'] or { cfg.view_distance.str() }).int()
	cfg.gamemode = values['gamemode'] or { cfg.gamemode }
	cfg.xbox_auth = to_bool(values['xbox-auth'] or { cfg.xbox_auth.str() })
	cfg.compression_threshold = (values['compression-threshold'] or {
		cfg.compression_threshold.str()
	}).int()
	cfg.generator = values['generator'] or { cfg.generator }
	cfg.debug = to_bool(values['debug'] or { cfg.debug.str() })
	return cfg
}

fn parse_flat_yaml(content string) map[string]string {
	mut values := map[string]string{}
	for raw_line in content.split_into_lines() {
		line := raw_line.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		idx := line.index(':') or { continue }
		key := line[..idx].trim_space()
		mut value := line[idx + 1..].trim_space()
		if comment := value.index(' #') {
			value = value[..comment].trim_space()
		}
		value = value.trim('"').trim("'")
		values[key] = value
	}
	return values
}

fn to_bool(value string) bool {
	return value.to_lower() in ['true', 'yes', 'on', '1']
}

fn write_default(path string, cfg Config) ! {
	content := '# Vedrock server configuration
motd: "${cfg.motd}"
sub-motd: "${cfg.sub_motd}"
address: "${cfg.address}"
port: ${cfg.port}
max-players: ${cfg.max_players}
view-distance: ${cfg.view_distance}
gamemode: "${cfg.gamemode}"
xbox-auth: ${cfg.xbox_auth}
compression-threshold: ${cfg.compression_threshold}
generator: "${cfg.generator}"
debug: ${cfg.debug}
'
	os.write_file(path, content)!
}

pub fn (c &Config) bind_address() string {
	return '${c.address}:${c.port}'
}
