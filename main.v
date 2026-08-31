module main

import os
import time
import sync.stdatomic
import server.conf
import server
import server.crash

// This is the reference/example entrypoint, not a fixed binary a user must
// use as-is. server.new(...) is a real library constructor. Compile your
// own program against the `server` module the same way.
fn main() {
	cfg := conf.load() or {
		eprintln('Failed to load config: ${err}')
		exit(1)
	}
	mut srv := server.new(settings: cfg) or {
		eprintln('Failed to start: ${err}')
		exit(1)
	}

	// Signal handlers must stay async signal-safe: no allocation, no locks,
	// no blocking I/O. Server.stop() does all three (logs, locks the hub,
	// blocks on wait_for_sessions_to_leave), so it must never run directly
	// inside the handler - doing so segfaults intermittently when the
	// interrupted thread is already inside libc (malloc, a lock) and the
	// handler reenters the same machinery.
	mut interrupted := stdatomic.new_atomic[bool](false)
	os.signal_opt(.int, fn [mut interrupted] (_ os.Signal) {
		interrupted.store(true)
	}) or {}
	spawn fn [mut srv, mut interrupted] () {
		for !interrupted.load() {
			time.sleep(50 * time.millisecond)
		}
		srv.stop()
		exit(0)
	}()

	srv.start() or {
		srv.log.error('Server stopped: ${err}')
		// A fatal startup/run error is our last chance to leave a trace before
		// exiting, drop a crash report so the failure is recoverable post mortem.
		if path := crash.write_dump(srv.cfg.crashdumps_dir, time.now().unix(), 'server stopped',
			err.msg())
		{
			srv.log.error('Wrote crash report to ${path}')
		}
		exit(1)
	}
}
