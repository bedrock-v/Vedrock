module config

import os
import toml

pub struct Config {
pub mut:
	motd           string = 'Vedrock Server'
	sub_motd       string = 'A V Bedrock server'
	address        string = '0.0.0.0'
	port           int    = 19132
	max_players    int    = 20
	view_distance  int    = 8
	gamemode       string = 'creative'
	debug          bool
}

const default_file = 'vedrock.toml'

pub fn load() !Config {
	return load_from(default_file)
}

pub fn load_from(path string) !Config {
	if !os.exists(path) {
		cfg := Config{}
		write_default(path, cfg)!
		return cfg
	}
	doc := toml.parse_file(path)!
	mut cfg := Config{}
	cfg.motd = doc.value_opt('motd') or { toml.Any(cfg.motd) }.string()
	cfg.sub_motd = doc.value_opt('sub-motd') or { toml.Any(cfg.sub_motd) }.string()
	cfg.address = doc.value_opt('address') or { toml.Any(cfg.address) }.string()
	cfg.port = doc.value_opt('port') or { toml.Any(cfg.port) }.int()
	cfg.max_players = doc.value_opt('max-players') or { toml.Any(cfg.max_players) }.int()
	cfg.view_distance = doc.value_opt('view-distance') or { toml.Any(cfg.view_distance) }.int()
	cfg.gamemode = doc.value_opt('gamemode') or { toml.Any(cfg.gamemode) }.string()
	cfg.debug = doc.value_opt('debug') or { toml.Any(cfg.debug) }.bool()
	return cfg
}

fn write_default(path string, cfg Config) ! {
	content := 'motd = "${cfg.motd}"
sub-motd = "${cfg.sub_motd}"
address = "${cfg.address}"
port = ${cfg.port}
max-players = ${cfg.max_players}
view-distance = ${cfg.view_distance}
gamemode = "${cfg.gamemode}"
debug = ${cfg.debug}
'
	os.write_file(path, content)!
}

pub fn (c &Config) bind_address() string {
	return '${c.address}:${c.port}'
}
