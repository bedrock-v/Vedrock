module default

import server.permission
import server.cmd

pub struct SeedCommand {}

pub fn (c SeedCommand) name() string {
	return 'seed'
}

pub fn (c SeedCommand) description() string {
	return 'Shows the seed of the world you are in'
}

pub fn (c SeedCommand) aliases() []string {
	return []
}

pub fn (c SeedCommand) permission() string {
	return permission.command_seed
}

pub fn (c SeedCommand) arguments() []cmd.Argument {
	return []
}

pub fn (c SeedCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	info := sender.world_info(sender.current_world_name()) or {
		sender.send_message(ctx.lang.t('cmd.world.none'))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.seed.body', {
		'Seed': info.seed.str()
	}))!
}
