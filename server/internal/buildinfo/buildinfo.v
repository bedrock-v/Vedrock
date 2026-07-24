module buildinfo

import os
import v.vmod

pub const name = 'Vedrock'
pub const version = resolve_version()
pub const git_hash = resolve_git_hash()

fn resolve_version() string {
	manifest := vmod.decode(@VMOD_FILE) or { return 'unknown' }
	if manifest.version == '' {
		return 'unknown'
	}
	return manifest.version
}

fn resolve_git_hash() string {
	rev := os.execute('git rev-parse --short HEAD')
	if rev.exit_code != 0 {
		return 'unknown'
	}
	hash := rev.output.trim_space()
	status := os.execute('git status --porcelain')
	if status.exit_code == 0 && status.output.trim_space() != '' {
		return '${hash}-dirty'
	}
	return hash
}
