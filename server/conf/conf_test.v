module conf

import os

fn test_load_generates_and_persists_bstats_uuid() {
	path := os.join_path(os.vtmp_dir(), 'vedrock_conf_bstats.yml')
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, 'motd: "Test"\nbstats: true\n')!

	cfg := load_from(path)!
	assert cfg.bstats
	assert cfg.bstats_uuid != ''
	assert os.read_file(path)!.contains('bstats-uuid: "${cfg.bstats_uuid}"')

	// The id must survive a restart, otherwise every boot looks like a new server.
	reloaded := load_from(path)!
	assert reloaded.bstats_uuid == cfg.bstats_uuid
}

fn test_load_reads_bstats_opt_out() {
	path := os.join_path(os.vtmp_dir(), 'vedrock_conf_bstats_off.yml')
	defer {
		os.rm(path) or {}
	}
	os.write_file(path, 'bstats: false\nbstats-uuid: "abc"\nbstats-log-failed: true\n')!

	cfg := load_from(path)!
	assert !cfg.bstats
	assert cfg.bstats_uuid == 'abc'
	assert cfg.bstats_log_failed
}
