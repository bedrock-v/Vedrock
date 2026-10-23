module main

import os
import time
import sync.stdatomic
import server
import server.network

fn main() {
	mut srv := server.new(
		listeners: [network.nethernet(network.NetherNetConfig{})]
	) or {
		eprintln('vedrock: ${err}')
		exit(1)
	}
	mut interrupted := stdatomic.new_atomic[bool](false)
	os.signal_opt(.int, fn [mut interrupted] (_ os.Signal) {
		interrupted.store(true)
	}) or { eprintln('vedrock: Ctrl+C will not shut down cleanly: ${err}') }
	spawn fn [mut srv, mut interrupted] () {
		for !interrupted.load() {
			time.sleep(50 * time.millisecond)
		}
		srv.close()
	}()
	srv.run()
}
