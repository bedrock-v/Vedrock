module default

import command

pub fn register_all(mut r command.Registry) {
	r.register(VersionCommand{})
	r.register(StatusCommand{})
	r.register(GamemodeCommand{})
}
