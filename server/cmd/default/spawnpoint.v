module default

import strconv
import server.permission
import server.cmd

pub struct SpawnpointCommand {}

pub fn (c SpawnpointCommand) name() string {
	return 'spawnpoint'
}

pub fn (c SpawnpointCommand) description() string {
	return 'Sets where a player respawns'
}

pub fn (c SpawnpointCommand) aliases() []string {
	return []
}

pub fn (c SpawnpointCommand) permission() string {
	return permission.command_spawnpoint
}

pub fn (c SpawnpointCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name:     'player'
			arg_optional: true
		},
		cmd.IntArgument{
			arg_name:     'x'
			arg_optional: true
		},
		cmd.IntArgument{
			arg_name:     'y'
			arg_optional: true
		},
		cmd.IntArgument{
			arg_name:     'z'
			arg_optional: true
		},
	]
}

// execute takes the target's current position when no coordinates are given,
// which is what the command is for most of the time.
pub fn (c SpawnpointCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	mut target := sender
	if ctx.args.len > 0 {
		target_name := ctx.args[0]
		target = sender.find_player(target_name) or {
			sender.send_message(ctx.lang.tf('cmd.player_not_found', {
				'Name': target_name
			}))!
			return
		}
	} else if !sender.is_player() {
		sender.send_message(ctx.lang.t('cmd.player_only'))!
		return
	}
	mut pos := target.position()
	if ctx.args.len >= 4 {
		x := strconv.atoi(ctx.args[1]) or {
			sender.send_message(ctx.lang.t('cmd.spawnpoint.usage'))!
			return
		}
		y := strconv.atoi(ctx.args[2]) or {
			sender.send_message(ctx.lang.t('cmd.spawnpoint.usage'))!
			return
		}
		z := strconv.atoi(ctx.args[3]) or {
			sender.send_message(ctx.lang.t('cmd.spawnpoint.usage'))!
			return
		}
		pos.x = f32(x)
		pos.y = f32(y)
		pos.z = f32(z)
	}
	target.set_spawn_point(pos.x, pos.y, pos.z)
	sender.send_message(ctx.lang.tf('cmd.spawnpoint.success', {
		'Name': target.name()
		'X':    int(pos.x).str()
		'Y':    int(pos.y).str()
		'Z':    int(pos.z).str()
	}))!
}
