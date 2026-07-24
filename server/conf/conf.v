module conf

import os
import protocol

pub struct Config {
pub mut:
	motd          string = 'Vedrock Server'
	sub_motd      string = 'A V Bedrock server'
	address       string = '0.0.0.0'
	port          int    = 19132
	max_players   int    = 20
	view_distance int    = 8
	gamemode      string = 'survival'
	difficulty    string = 'normal'
	xbox_auth     bool   = true
	// encryption negotiates Bedrock protocol encryption. Off by default - the
	// implementation is spec-complete but not yet verified against a real client,
	// so leaving it off keeps sessions cleartext and connectable.
	encryption            bool
	compression_threshold int    = 256
	generator             string = 'flat'
	language              string = 'en'
	resource_packs        bool   = true
	resource_packs_dir    string = 'resource_packs'
	force_resource_packs  bool
	allow_client_packs    bool = true
	cdn_packs             string
	default_world         string = 'world'
	load_all_worlds       bool
	debug                 bool
	// worlds_dir/crashdumps_dir/*_file are per instance.
	worlds_dir              string = 'worlds'
	players_dir             string = 'players'
	crashdumps_dir          string = 'crashdumps'
	ops_file                string = 'ops.txt'
	permissions_file        string = 'permissions.yml'
	player_permissions_file string = 'player_permissions.yml'
	whitelist_file          string = 'whitelist.txt'
	// config_file is set automatically by load_from to the path it was
	// loaded from, so runtime settings changes (e.g. /difficulty) persist
	// back to the same per instance file this Config actually came from.
	config_file string = default_file
}

const default_file = 'vedrock.yml'

pub fn load() !Config {
	return load_from(default_file)
}

pub fn load_from(path string) !Config {
	if !os.exists(path) {
		mut cfg := if should_run_wizard() { run_wizard() } else { Config{} }
		cfg.config_file = path
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
	cfg.difficulty = values['difficulty'] or { cfg.difficulty }
	cfg.xbox_auth = to_bool(values['xbox-auth'] or { cfg.xbox_auth.str() })
	cfg.encryption = to_bool(values['encryption'] or { cfg.encryption.str() })
	cfg.compression_threshold = (values['compression-threshold'] or {
		cfg.compression_threshold.str()
	}).int()
	// the threshold is sent to clients as a u16 in NetworkSettings
	if cfg.compression_threshold < 0 {
		cfg.compression_threshold = 0
	} else if cfg.compression_threshold > 65535 {
		cfg.compression_threshold = 65535
	}
	cfg.generator = values['generator'] or { cfg.generator }
	cfg.language = values['language'] or { cfg.language }
	cfg.resource_packs = to_bool(values['resource-packs'] or { cfg.resource_packs.str() })
	cfg.resource_packs_dir = values['resource-packs-dir'] or { cfg.resource_packs_dir }
	cfg.force_resource_packs = to_bool(values['force-resource-packs'] or {
		cfg.force_resource_packs.str()
	})
	cfg.allow_client_packs = to_bool(values['allow-client-packs'] or {
		cfg.allow_client_packs.str()
	})
	cfg.cdn_packs = values['cdn-packs'] or { cfg.cdn_packs }
	cfg.default_world = values['default-world'] or { cfg.default_world }
	cfg.load_all_worlds = to_bool(values['load-all-worlds'] or { cfg.load_all_worlds.str() })
	cfg.debug = to_bool(values['debug'] or { cfg.debug.str() })
	cfg.worlds_dir = values['worlds-dir'] or { cfg.worlds_dir }
	cfg.players_dir = values['players-dir'] or { cfg.players_dir }
	cfg.crashdumps_dir = values['crashdumps-dir'] or { cfg.crashdumps_dir }
	cfg.ops_file = values['ops-file'] or { cfg.ops_file }
	cfg.permissions_file = values['permissions-file'] or { cfg.permissions_file }
	cfg.player_permissions_file = values['player-permissions-file'] or {
		cfg.player_permissions_file
	}
	cfg.whitelist_file = values['whitelist-file'] or { cfg.whitelist_file }
	cfg.config_file = path
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
difficulty: "${cfg.difficulty}"
xbox-auth: ${cfg.xbox_auth}
encryption: ${cfg.encryption}
compression-threshold: ${cfg.compression_threshold}
generator: "${cfg.generator}"
language: "${cfg.language}"
resource-packs: ${cfg.resource_packs}
resource-packs-dir: "${cfg.resource_packs_dir}"
force-resource-packs: ${cfg.force_resource_packs}
allow-client-packs: ${cfg.allow_client_packs}
# cdn-packs format: uuid,version,url,size ; separated by ";"
cdn-packs: "${cfg.cdn_packs}"
default-world: "${cfg.default_world}"
load-all-worlds: ${cfg.load_all_worlds}
debug: ${cfg.debug}
worlds-dir: "${cfg.worlds_dir}"
players-dir: "${cfg.players_dir}"
crashdumps-dir: "${cfg.crashdumps_dir}"
ops-file: "${cfg.ops_file}"
permissions-file: "${cfg.permissions_file}"
player-permissions-file: "${cfg.player_permissions_file}"
whitelist-file: "${cfg.whitelist_file}"
'
	os.write_file(path, content)!
}

pub fn (c &Config) bind_address() string {
	return '${c.address}:${c.port}'
}

// difficulty_from_string maps a human-readable difficulty name to its protocol
// constant. Unknown values fall back to normal.
pub fn difficulty_from_string(s string) int {
	return match s.to_lower() {
		'peaceful', 'p', '0' { protocol.difficulty_peaceful }
		'easy', 'e', '1' { protocol.difficulty_easy }
		'normal', 'n', '2' { protocol.difficulty_normal }
		'hard', 'h', '3' { protocol.difficulty_hard }
		else { protocol.difficulty_normal }
	}
}

// difficulty_name returns the canonical name for a protocol difficulty constant.
pub fn difficulty_name(value int) string {
	return match value {
		protocol.difficulty_peaceful { 'peaceful' }
		protocol.difficulty_easy { 'easy' }
		protocol.difficulty_normal { 'normal' }
		protocol.difficulty_hard { 'hard' }
		else { 'normal' }
	}
}

// update_difficulty_in_file rewrites the difficulty line in a vedrock.yml shaped
// file. Callers pass the specific Config's own config_file (not a shared
// default), so persisting a runtime difficulty change never touches another
// instance's settings file.
pub fn update_difficulty_in_file(path string, new_name string) ! {
	mut lines := os.read_lines(path)!
	mut found := false
	for mut line in lines {
		if line.starts_with('difficulty:') {
			line = 'difficulty: "${new_name}"'
			found = true
			break
		}
	}
	if !found {
		return error('difficulty key not found in ${path}')
	}
	os.write_file(path, lines.join_lines())!
}
