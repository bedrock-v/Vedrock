module permission

import os

pub const default_whitelist_file = 'whitelist.txt'

const enabled_prefix = '# whitelist-enabled: '

pub struct Whitelist {
mut:
	path    string
	enabled bool
	names   map[string]bool
}

pub fn load_whitelist(path string) !Whitelist {
	mut list := Whitelist{
		path: path
	}
	if !os.exists(path) {
		list.save()!
		return list
	}
	content := os.read_file(path)!
	for raw_line in content.split_into_lines() {
		line := raw_line.trim_space()
		if line == '' {
			continue
		}
		if line.starts_with(enabled_prefix) {
			list.enabled = line[enabled_prefix.len..].trim_space().to_lower() == 'true'
			continue
		}
		if line.starts_with('#') {
			continue
		}
		list.names[line.to_lower()] = true
	}
	return list
}

pub fn (w &Whitelist) is_enabled() bool {
	return w.enabled
}

pub fn (mut w Whitelist) set_enabled(value bool) ! {
	w.enabled = value
	w.save()!
}

// is_allowed reports whether name may join: always true while the whitelist
// is disabled, otherwise only true for names explicitly added.
pub fn (w &Whitelist) is_allowed(name string) bool {
	if !w.enabled {
		return true
	}
	return w.names[name.to_lower()]
}

pub fn (w &Whitelist) is_whitelisted(name string) bool {
	return w.names[name.to_lower()]
}

pub fn (mut w Whitelist) add(name string) ! {
	w.names[name.to_lower()] = true
	w.save()!
}

pub fn (mut w Whitelist) remove(name string) ! {
	w.names.delete(name.to_lower())
	w.save()!
}

pub fn (w &Whitelist) names_list() []string {
	mut out := []string{cap: w.names.len}
	for name, _ in w.names {
		out << name
	}
	return out
}

fn (w &Whitelist) save() ! {
	mut lines := []string{}
	lines << '${enabled_prefix}${w.enabled}'
	for name, _ in w.names {
		lines << name
	}
	os.write_file(w.path, lines.join('\n') + '\n')!
}
