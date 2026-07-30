module main

import os
import time
import server.conf
import server
import server.crash

fn main() {
	cfg := conf.load() or {
		eprintln('Failed to load config: ${err}')
		exit(1)
	}
	mut srv := server.new(cfg)
	os.signal_opt(.int, fn [mut srv] (_ os.Signal) {
		srv.stop()
		exit(0)
	}) or {}
	srv.start() or {
		srv.log.error('Server stopped: ${err}')
		// A fatal startup/run error is our last chance to leave a trace before
		// exiting - drop a crash report so the failure is recoverable post-mortem.
		if path := crash.write_dump(server.crashdumps_dir, time.now().unix(), 'server stopped', err.msg()) {
			srv.log.error('Wrote crash report to ${path}')
		}
		exit(1)
	}
}
