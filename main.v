module main

import os
import server.conf
import server

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
		exit(1)
	}
}
