module crash

import os

fn test_write_dump_creates_file() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_crash_test_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	path := write_dump(dir, i64(1720000000), 'boom', 'stack: foo -> bar') or {
		assert false, 'write_dump failed: ${err}'
		return
	}
	assert os.exists(path)
	assert path.ends_with('crash-1720000000.txt')
	text := os.read_file(path) or {
		assert false, 'could not read dump: ${err}'
		return
	}
	assert text.contains('boom')
	assert text.contains('stack: foo -> bar')
	assert text.contains(v_version_note)
	assert text.contains('1720000000')
}

fn test_write_dump_makes_missing_dir() {
	base := os.join_path(os.vtmp_dir(), 'vedrock_crash_nested_${os.getpid()}')
	dir := os.join_path(base, 'a', 'b')
	defer {
		os.rmdir_all(base) or {}
	}
	path := write_dump(dir, i64(42), 'title', '') or {
		assert false, 'write_dump failed: ${err}'
		return
	}
	assert os.exists(path)
}

fn test_build_report_omits_empty_context() {
	report := build_report(i64(7), 'panic', '')
	assert report.contains('title: panic')
	assert !report.contains('context:')
}

fn test_build_report_includes_context() {
	report := build_report(i64(7), 'panic', 'details here')
	assert report.contains('context:')
	assert report.contains('details here')
}
