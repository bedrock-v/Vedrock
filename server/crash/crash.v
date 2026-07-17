module crash

import os

// v_version_note describes the pinned compiler this build is expected to run
// under. Kept as a note in the dump so a crash report is self-describing even
// when the reporter no longer knows which V built the binary.
pub const v_version_note = 'built with V 0.5.2 (f1ef640)'

// write_dump writes a timestamped crash report into dir and returns the path it
// wrote. The timestamp is passed in rather than read from the clock so callers
// stay testable - no hidden Date.now() in library code.
pub fn write_dump(dir string, stamp i64, title string, details string) !string {
	os.mkdir_all(dir)!
	path := os.join_path(dir, 'crash-${stamp}.txt')
	report := build_report(stamp, title, details)
	os.write_file(path, report)!
	return path
}

// build_report renders the report body. Split out from write_dump so tests can
// assert on the content without touching the filesystem.
pub fn build_report(stamp i64, title string, details string) string {
	mut b := []string{}
	b << '=== Vedrock crash report ==='
	b << 'time: ${stamp}'
	b << 'title: ${title}'
	b << v_version_note
	if details != '' {
		b << ''
		b << 'context:'
		b << details
	}
	b << ''
	return b.join('\n')
}
