module default

import strconv
import server.permission
import server.cmd

pub struct TeleportCommand {}

pub fn (c TeleportCommand) name() string {
	return 'tp'
}

pub fn (c TeleportCommand) description() string {
	return 'Teleports yourself or another player'
}

pub fn (c TeleportCommand) aliases() []string {
	return ['teleport']
}

pub fn (c TeleportCommand) permission() string {
	return permission.command_teleport_self
}

pub fn (c TeleportCommand) arguments() []cmd.Argument {
	return [
		cmd.TargetArgument{
			arg_name: 'target'
		},
		cmd.TextArgument{
			arg_name:     'rest'
			arg_optional: true
		},
	]
}

fn parse_coord(raw string) ?f32 {
	v := strconv.atof64(raw) or { return none }
	return f32(v)
}

pub fn (c TeleportCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	match ctx.args.len {
		1 {
			if !sender.is_player() {
				sender.send_message(ctx.lang.t('cmd.player_only'))!
				return
			}
			target_name := ctx.args[0]
			mut dest := sender.find_player(target_name) or {
				sender.send_message(ctx.lang.tf('cmd.player_not_found', {
					'Name': target_name
				}))!
				return
			}
			x, y, z := dest.position()
			sender.teleport(x, y, z)
			sender.send_message(ctx.lang.tf('cmd.teleport.moved', {
				'X': '${x:.1f}'
				'Y': '${y:.1f}'
				'Z': '${z:.1f}'
			}))!
		}
		3 {
			if !sender.is_player() {
				sender.send_message(ctx.lang.t('cmd.player_only'))!
				return
			}
			x := parse_coord(ctx.args[0]) or {
				sender.send_message(ctx.lang.t('cmd.teleport.usage'))!
				return
			}
			y := parse_coord(ctx.args[1]) or {
				sender.send_message(ctx.lang.t('cmd.teleport.usage'))!
				return
			}
			z := parse_coord(ctx.args[2]) or {
				sender.send_message(ctx.lang.t('cmd.teleport.usage'))!
				return
			}
			sender.teleport(x, y, z)
			sender.send_message(ctx.lang.tf('cmd.teleport.moved', {
				'X': '${x:.1f}'
				'Y': '${y:.1f}'
				'Z': '${z:.1f}'
			}))!
		}
		2 {
			if !sender.has_permission(permission.command_teleport_other) {
				sender.send_message(ctx.lang.t('cmd.no_permission'))!
				return
			}
			target_name := ctx.args[0]
			mut target := sender.find_player(target_name) or {
				sender.send_message(ctx.lang.tf('cmd.player_not_found', {
					'Name': target_name
				}))!
				return
			}
			dest_name := ctx.args[1]
			mut dest := sender.find_player(dest_name) or {
				sender.send_message(ctx.lang.tf('cmd.player_not_found', {
					'Name': dest_name
				}))!
				return
			}
			x, y, z := dest.position()
			target.teleport(x, y, z)
			sender.send_message(ctx.lang.tf('cmd.teleport.moved_other', {
				'Name': target.name()
				'X':    '${x:.1f}'
				'Y':    '${y:.1f}'
				'Z':    '${z:.1f}'
			}))!
		}
		4 {
			if !sender.has_permission(permission.command_teleport_other) {
				sender.send_message(ctx.lang.t('cmd.no_permission'))!
				return
			}
			target_name := ctx.args[0]
			mut target := sender.find_player(target_name) or {
				sender.send_message(ctx.lang.tf('cmd.player_not_found', {
					'Name': target_name
				}))!
				return
			}
			x := parse_coord(ctx.args[1]) or {
				sender.send_message(ctx.lang.t('cmd.teleport.usage'))!
				return
			}
			y := parse_coord(ctx.args[2]) or {
				sender.send_message(ctx.lang.t('cmd.teleport.usage'))!
				return
			}
			z := parse_coord(ctx.args[3]) or {
				sender.send_message(ctx.lang.t('cmd.teleport.usage'))!
				return
			}
			target.teleport(x, y, z)
			sender.send_message(ctx.lang.tf('cmd.teleport.moved_other', {
				'Name': target.name()
				'X':    '${x:.1f}'
				'Y':    '${y:.1f}'
				'Z':    '${z:.1f}'
			}))!
		}
		else {
			sender.send_message(ctx.lang.t('cmd.teleport.usage'))!
		}
	}
}
