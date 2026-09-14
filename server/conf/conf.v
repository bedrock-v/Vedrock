module conf

import os
import toml
import bedrock_v.protocol.current as proto

// default_join_port is the port a Bedrock client tries first when it is
// given an address with no port of its own.
pub const default_join_port = 19132

pub struct Config {
pub mut:
	motd     string = 'Vedrock Server'
	sub_motd string = 'A V Bedrock server'
	address  string = '0.0.0.0'
	// port is where a client joining by address reaches the server. LAN
	// discovery is not configurable: a client only ever broadcasts to 7551.
	port          int    = default_join_port
	max_players   int    = 20
	view_distance int    = 8
	gamemode      string = 'survival'
	difficulty    string = 'normal'
	// xbox_auth verifies the Xbox Live chain in the client's Login packet. It
	// says nothing about the transport: NetherNet's own identity assertion is
	// a separate binding, and the game omits it more often than not.
	xbox_auth bool = true
	// require_identity rejects a NetherNet offer that carries no identity
	// assertion. On by default: an anonymous offer gives up the binding between
	// the peer's key and the connection, which is the only thing keeping a login
	// chain captured elsewhere from being replayed onto it. Turn it off for a LAN
	// where the game connects without one and the network is trusted.
	require_identity bool = true
	// verify_identity_token checks the identity token in an offer against
	// Microsoft's published signing keys before the offer is answered. Off leaves
	// the token unverified: the peer still has to hold the key its token names,
	// but the token itself may say anything.
	verify_identity_token bool = true
	// ice_servers are "stun:host:port" or "turn:host:port" entries used to gather
	// candidates. A LAN needs none; a server on the internet whose peers sit
	// behind NAT usually needs at least STUN.
	ice_servers []string
	// advertise_addresses, when non-empty, is the only set of local addresses
	// put into an answer. Set it on a host whose interface list includes
	// container or overlay addresses nothing outside can reach.
	advertise_addresses []string
	// media_port_min and media_port_max bound the UDP ports media binds. Zero
	// lets the kernel pick a port per peer, which nobody can write a firewall
	// rule for.
	media_port_min int
	media_port_max int
	// encryption negotiates Bedrock protocol encryption. NetherNet already
	// encrypts every byte over DTLS and reports so, in which case the handshake
	// is skipped no matter what this says.
	encryption            bool   = true
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
	// identity_file stores the key the server presents in its NetherNet answers,
	// as PEM. Keeping it means a client that remembers the server still
	// recognises it after a restart, so it is worth sharing across a fleet that
	// should look like one operator.
	identity_file string = 'keys/identity.pem'
	// identity_domain names the issuer of that key to a joining player. Empty
	// uses the MOTD, which is the name they already know the server by. It is
	// display text, so changing it costs nothing; changing the key costs every
	// player a fresh trust prompt.
	identity_domain string
	// config_file is set automatically by load_from to the path it was
	// loaded from, so runtime settings changes (e.g. /difficulty) persist
	// back to the same per instance file this Config actually came from.
	config_file string = default_file
}

const default_file = 'vedrock.toml'

pub fn load() !Config {
	return load_from(default_file)
}

pub fn load_from(path string) !Config {
	mut cfg := Config{}
	cfg.config_file = path
	if !os.exists(path) {
		write_default(path, cfg)!
		return cfg
	}
	doc := toml.parse_file(path)!
	cfg.motd = text(doc, 'server.motd', cfg.motd)
	cfg.sub_motd = text(doc, 'server.sub-motd', cfg.sub_motd)
	cfg.max_players = number(doc, 'server.max-players', cfg.max_players)
	cfg.gamemode = text(doc, 'server.gamemode', cfg.gamemode)
	cfg.difficulty = text(doc, 'server.difficulty', cfg.difficulty)
	cfg.language = text(doc, 'server.language', cfg.language)
	cfg.debug = flag(doc, 'server.debug', cfg.debug)

	cfg.address = text(doc, 'network.address', cfg.address)
	cfg.port = number(doc, 'network.port', cfg.port)
	cfg.view_distance = number(doc, 'network.view-distance', cfg.view_distance)
	cfg.xbox_auth = flag(doc, 'network.xbox-auth', cfg.xbox_auth)
	cfg.require_identity = flag(doc, 'network.require-identity', cfg.require_identity)
	cfg.verify_identity_token = flag(doc, 'network.verify-identity-token',
		cfg.verify_identity_token)
	cfg.ice_servers = list(doc, 'network.ice-servers', cfg.ice_servers)
	cfg.advertise_addresses = list(doc, 'network.advertise-addresses', cfg.advertise_addresses)
	cfg.media_port_min = number(doc, 'network.media-port-min', cfg.media_port_min)
	cfg.media_port_max = number(doc, 'network.media-port-max', cfg.media_port_max)
	cfg.encryption = flag(doc, 'network.encryption', cfg.encryption)
	cfg.compression_threshold = number(doc, 'network.compression-threshold',
		cfg.compression_threshold)
	// the threshold is sent to clients as a u16 in NetworkSettings
	if cfg.compression_threshold < 0 {
		cfg.compression_threshold = 0
	} else if cfg.compression_threshold > 65535 {
		cfg.compression_threshold = 65535
	}

	cfg.generator = text(doc, 'world.generator', cfg.generator)
	cfg.default_world = text(doc, 'world.default', cfg.default_world)
	cfg.load_all_worlds = flag(doc, 'world.load-all', cfg.load_all_worlds)

	cfg.resource_packs = flag(doc, 'resource-packs.enabled', cfg.resource_packs)
	cfg.resource_packs_dir = text(doc, 'resource-packs.dir', cfg.resource_packs_dir)
	cfg.force_resource_packs = flag(doc, 'resource-packs.force', cfg.force_resource_packs)
	cfg.allow_client_packs = flag(doc, 'resource-packs.allow-client-packs', cfg.allow_client_packs)
	cfg.cdn_packs = text(doc, 'resource-packs.cdn-packs', cfg.cdn_packs)

	cfg.worlds_dir = text(doc, 'paths.worlds-dir', cfg.worlds_dir)
	cfg.players_dir = text(doc, 'paths.players-dir', cfg.players_dir)
	cfg.crashdumps_dir = text(doc, 'paths.crashdumps-dir', cfg.crashdumps_dir)
	cfg.ops_file = text(doc, 'paths.ops-file', cfg.ops_file)
	cfg.permissions_file = text(doc, 'paths.permissions-file', cfg.permissions_file)
	cfg.player_permissions_file = text(doc, 'paths.player-permissions-file',
		cfg.player_permissions_file)
	cfg.whitelist_file = text(doc, 'paths.whitelist-file', cfg.whitelist_file)
	cfg.identity_file = text(doc, 'paths.identity-file', cfg.identity_file)
	cfg.identity_domain = text(doc, 'network.identity-domain', cfg.identity_domain)
	return cfg
}

// A key the file leaves out keeps the struct default, so a partial config
// stays valid and new settings do not need a rewrite of every existing file.
fn text(doc toml.Doc, key string, fallback string) string {
	value := doc.value_opt(key) or { return fallback }
	return value.string()
}

fn number(doc toml.Doc, key string, fallback int) int {
	value := doc.value_opt(key) or { return fallback }
	return value.int()
}

// list reads an array of strings, dropping empty entries so a trailing comma or
// a blank line in the file does not turn into an address nothing matches.
fn list(doc toml.Doc, key string, fallback []string) []string {
	value := doc.value_opt(key) or { return fallback }
	mut out := []string{}
	for entry in value.array() {
		item := entry.string().trim_space()
		if item != '' {
			out << item
		}
	}
	return out
}

fn flag(doc toml.Doc, key string, fallback bool) bool {
	value := doc.value_opt(key) or { return fallback }
	return value.bool()
}

fn write_default(path string, cfg Config) ! {
	content := '# Vedrock server configuration

[server]
motd = "${cfg.motd}"
sub-motd = "${cfg.sub_motd}"
max-players = ${cfg.max_players}
gamemode = "${cfg.gamemode}"
difficulty = "${cfg.difficulty}"
language = "${cfg.language}"
debug = ${cfg.debug}

[network]
address = "${cfg.address}"
port = ${cfg.port}
view-distance = ${cfg.view_distance}
xbox-auth = ${cfg.xbox_auth}
require-identity = ${cfg.require_identity}
verify-identity-token = ${cfg.verify_identity_token}
encryption = ${cfg.encryption}
compression-threshold = ${cfg.compression_threshold}
# Shown to a joining player as the issuer of the server key. Empty uses the MOTD.
identity-domain = "${cfg.identity_domain}"
# STUN/TURN servers used to gather ICE candidates, e.g. ["stun:stun.l.google.com:19302"]
ice-servers = ${toml_list(cfg.ice_servers)}
# Announce only these local addresses. Empty announces every address ICE gathers.
advertise-addresses = ${toml_list(cfg.advertise_addresses)}
# UDP port range media binds. 0 lets the kernel pick a port per peer.
media-port-min = ${cfg.media_port_min}
media-port-max = ${cfg.media_port_max}

[world]
generator = "${cfg.generator}"
default = "${cfg.default_world}"
load-all = ${cfg.load_all_worlds}

[resource-packs]
enabled = ${cfg.resource_packs}
dir = "${cfg.resource_packs_dir}"
force = ${cfg.force_resource_packs}
allow-client-packs = ${cfg.allow_client_packs}
# cdn-packs format: uuid,version,url,size,content-key ; separated by ";"
cdn-packs = "${cfg.cdn_packs}"

[paths]
worlds-dir = "${cfg.worlds_dir}"
players-dir = "${cfg.players_dir}"
crashdumps-dir = "${cfg.crashdumps_dir}"
ops-file = "${cfg.ops_file}"
permissions-file = "${cfg.permissions_file}"
player-permissions-file = "${cfg.player_permissions_file}"
whitelist-file = "${cfg.whitelist_file}"
identity-file = "${cfg.identity_file}"
'
	os.write_file(path, content)!
}

// toml_list renders a string array as a TOML inline array.
fn toml_list(values []string) string {
	mut quoted := []string{cap: values.len}
	for value in values {
		quoted << '"${value}"'
	}
	return '[${quoted.join(', ')}]'
}

pub fn (c &Config) bind_address() string {
	return '${c.address}:${c.port}'
}

// difficulty_from_string maps a human-readable difficulty name to its protocol
// constant. Unknown values fall back to normal.
pub fn difficulty_from_string(s string) int {
	return match s.to_lower() {
		'peaceful', 'p', '0' { proto.difficulty_peaceful }
		'easy', 'e', '1' { proto.difficulty_easy }
		'normal', 'n', '2' { proto.difficulty_normal }
		'hard', 'h', '3' { proto.difficulty_hard }
		else { proto.difficulty_normal }
	}
}

// difficulty_name returns the canonical name for a protocol difficulty constant.
pub fn difficulty_name(value int) string {
	return match value {
		proto.difficulty_peaceful { 'peaceful' }
		proto.difficulty_easy { 'easy' }
		proto.difficulty_normal { 'normal' }
		proto.difficulty_hard { 'hard' }
		else { 'normal' }
	}
}

// update_difficulty_in_file rewrites the difficulty line in a vedrock.toml
// shaped file. Callers pass the specific Config's own config_file (not a shared
// default), so persisting a runtime difficulty change never touches another
// instance's settings file.
pub fn update_difficulty_in_file(path string, new_name string) ! {
	mut lines := os.read_lines(path)!
	mut found := false
	for mut line in lines {
		if line.trim_space().starts_with('difficulty =') {
			line = 'difficulty = "${new_name}"'
			found = true
			break
		}
	}
	if !found {
		return error('difficulty key not found in ${path}')
	}
	os.write_file(path, lines.join_lines())!
}
