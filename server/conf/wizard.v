module conf

import os
import server.permission

fn should_run_wizard() bool {
	if '--no-wizard' in os.args {
		return false
	}
	if os.getenv('VEDROCK_NO_WIZARD') != '' {
		return false
	}
	return os.is_atty(0) > 0
}

fn run_wizard() Config {
	println('')
	println('=== Vedrock first-run setup ===')
	println("No vedrock.yml found - let's get the basics configured.")
	println('Press Enter on any question to accept the default shown in [brackets].')
	println('')
	accept_license() or {
		println('License not accepted, exiting.')
		exit(1)
	}

	mut cfg := Config{}
	cfg.language = ask_language()
	cfg.motd = ask_string('Server name (MOTD)', cfg.motd)
	cfg.sub_motd = ask_string('Sub-MOTD', cfg.sub_motd)
	cfg.port = ask_port('Port', cfg.port)
	cfg.gamemode = ask_gamemode('Default gamemode', cfg.gamemode)
	cfg.max_players = ask_positive_int('Max players', cfg.max_players)
	cfg.view_distance = ask_positive_int('View distance (chunks)', cfg.view_distance)
	cfg.xbox_auth = ask_yes_no('Require Xbox Live authentication?', cfg.xbox_auth)
	ask_first_operator()

	println('')
	println('=== Summary ===')
	println('motd: ${cfg.motd}')
	println('sub-motd: ${cfg.sub_motd}')
	println('port: ${cfg.port}')
	println('gamemode: ${cfg.gamemode}')
	println('max-players: ${cfg.max_players}')
	println('view-distance: ${cfg.view_distance}')
	println('xbox-auth: ${cfg.xbox_auth}')
	println('language: ${cfg.language}')
	println('Writing vedrock.yml and starting the server...')
	println('')
	return cfg
}

fn accept_license() ! {
	println('Vedrock is licensed under the GNU Lesser General Public License v3.0 (LGPL-3.0).')
	println('Full text: LICENSE (in this directory).')
	if !parse_yes_no(os.input('Do you accept the license terms? [y/N]: '), false) {
		return error('license declined')
	}
}

fn ask_language() string {
	codes := discover_languages()
	if codes.len == 0 {
		return 'en'
	}
	println('Available languages: ${codes.join(', ')}')
	mut result := 'en'
	for {
		raw := os.input('Language [en]: ').trim_space()
		code := if raw == '' { 'en' } else { raw }
		if code in codes {
			result = code
			break
		}
		println('Unknown language "${code}" - pick one of: ${codes.join(', ')}')
	}
	return result
}

// discover_languages lists the language codes available under "lang/".
fn discover_languages() []string {
	mut codes := []string{}
	for entry in os.ls('lang') or { return codes } {
		if entry.ends_with('.toml') {
			codes << entry.trim_string_right('.toml')
		}
	}
	codes.sort()
	return codes
}

fn ask_string(label string, default string) string {
	raw := os.input('${label} [${default}]: ').trim_space()
	return if raw == '' { default } else { raw }
}

fn ask_port(label string, default int) int {
	mut result := default
	for {
		raw := os.input('${label} [${default}]: ').trim_space()
		if port := parse_port(raw, default) {
			result = port
			break
		}
		println('Enter a port number between 1 and 65535.')
	}
	return result
}

fn ask_gamemode(label string, default string) string {
	mut result := default
	for {
		raw :=
			os.input('${label} (survival/creative/adventure/spectator) [${default}]: ').trim_space()
		if gamemode := parse_gamemode(raw, default) {
			result = gamemode
			break
		}
		println('Enter one of: survival, creative, adventure, spectator.')
	}
	return result
}

fn ask_positive_int(label string, default int) int {
	mut result := default
	for {
		raw := os.input('${label} [${default}]: ').trim_space()
		if value := parse_positive_int(raw, default) {
			result = value
			break
		}
		println('Enter a positive whole number.')
	}
	return result
}

fn ask_yes_no(label string, default bool) bool {
	hint := if default { 'Y/n' } else { 'y/N' }
	raw := os.input('${label} [${hint}]: ')
	return parse_yes_no(raw, default)
}

fn ask_first_operator() {
	name := os.input('First server operator username (blank to skip): ').trim_space()
	if name == '' {
		return
	}
	mut ops := permission.load_ops(permission.default_ops_file) or {
		println('Could not load ops file: ${err}')
		return
	}
	ops.add(name) or { println('Could not add "${name}" as operator: ${err}') }
}

const valid_gamemodes = ['survival', 'creative', 'adventure', 'spectator']

fn parse_port(raw string, default int) ?int {
	value := if raw.trim_space() == '' { default } else { raw.trim_space().int() }
	if value < 1 || value > 65535 {
		return none
	}
	return value
}

fn parse_gamemode(raw string, default string) ?string {
	value := if raw.trim_space() == '' { default } else { raw.trim_space().to_lower() }
	if value !in valid_gamemodes {
		return none
	}
	return value
}

fn parse_positive_int(raw string, default int) ?int {
	value := if raw.trim_space() == '' { default } else { raw.trim_space().int() }
	if value < 1 {
		return none
	}
	return value
}

fn parse_yes_no(raw string, default bool) bool {
	value := raw.trim_space().to_lower()
	if value == '' {
		return default
	}
	return value in ['y', 'yes']
}
