module main

import os
import time
import server.conf
import server
import server.crash
import server.event

// GreetHandler sends a test message to every player as they join. Embeds
// event.NopHandler so it only needs to override the one event it cares about.
struct GreetHandler {
	event.NopHandler
}

fn (mut h GreetHandler) on_player_join(mut ctx event.Context[event.JoinData]) {
	ctx.val.player.send_message('test') or {}
}

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
	srv.register_event(&GreetHandler{}, .normal)
	os.signal_opt(.int, fn [mut srv] (_ os.Signal) {
		srv.stop()
		exit(0)
	}) or {}
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
