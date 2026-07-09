module default

import server.cmd

pub fn register_all(mut r cmd.Registry) {
	r.register(VersionCommand{})
	r.register(StatusCommand{})
	r.register(GamemodeCommand{})
}
