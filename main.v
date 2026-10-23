module main

import server
import server.network

fn main() {
	mut srv := server.new(
		listeners: [network.nethernet(network.NetherNetConfig{})]
	) or {
		eprintln('vedrock: ${err}')
		exit(1)
	}
	srv.run()
}
