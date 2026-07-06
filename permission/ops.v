module permission

import os

pub const default_ops_file = 'ops.txt'

pub struct OpList {
mut:
	path string
	names map[string]bool
}

pub fn load_ops(path string) !OpList {
	mut list := OpList{
		path: path
	}
	if !os.exists(path) {
		list.save()!
		return list
	}
	content := os.read_file(path)!
	for raw_line in content.split_into_lines() {
		name := raw_line.trim_space()
		if name == '' || name.starts_with('#') {
			continue
		}
		list.names[name.to_lower()] = true
	}
	return list
}

pub fn (o &OpList) is_op(name string) bool {
	return o.names[name.to_lower()]
}

pub fn (mut o OpList) add(name string) ! {
	o.names[name.to_lower()] = true
	o.save()!
}

pub fn (mut o OpList) remove(name string) ! {
	o.names.delete(name.to_lower())
	o.save()!
}

fn (o &OpList) save() ! {
	mut lines := []string{}
	for name, _ in o.names {
		lines << name
	}
	os.write_file(o.path, lines.join('\n') + '\n')!
}
