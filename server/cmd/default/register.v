module default

import server.cmd

pub fn register_all(mut r cmd.Registry) {
	r.register(VersionCommand{})
	r.register(StatusCommand{})
	r.register(GamemodeCommand{})
	r.register(OpCommand{})
	r.register(DeopCommand{})
	r.register(WhitelistCommand{})
	r.register(KillCommand{})
	r.register(TeleportCommand{})
	r.register(ClearCommand{})
	r.register(GiveCommand{})
	r.register(DifficultyCommand{})
	r.register(SayCommand{})
	r.register(TitleCommand{})
}
