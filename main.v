module main

import server
import server.transport.nethernet

fn main() {
	mut srv := server.new(
		listeners: [nethernet.listener(nethernet.Config{})]
	) or {
		eprintln('vedrock: ${err}')
		exit(1)
	}
	srv.run()
}
