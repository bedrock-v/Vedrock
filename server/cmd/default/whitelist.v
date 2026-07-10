module default

import server.permission
import server.cmd

pub struct WhitelistCommand {}

pub fn (c WhitelistCommand) name() string {
	return 'whitelist'
}

pub fn (c WhitelistCommand) description() string {
	return 'Manages the server whitelist'
}

pub fn (c WhitelistCommand) aliases() []string {
	return []
}

pub fn (c WhitelistCommand) permission() string {
	return permission.command_whitelist
}

pub fn (c WhitelistCommand) arguments() []cmd.Argument {
	return [
		cmd.StringEnumArgument{
			arg_name: 'action'
			values:   ['add', 'remove', 'on', 'off', 'list']
		},
		cmd.StringArgument{
			arg_name:     'player'
			arg_optional: true
		},
	]
}

pub fn (c WhitelistCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	action := ctx.args[0].to_lower()
	match action {
		'add' {
			if ctx.args.len < 2 {
				sender.send_message(ctx.lang.t('cmd.whitelist.usage'))!
				return
			}
			sender.whitelist_add(ctx.args[1])
			sender.send_message(ctx.lang.tf('cmd.whitelist.added', {
				'Name': ctx.args[1]
			}))!
		}
		'remove' {
			if ctx.args.len < 2 {
				sender.send_message(ctx.lang.t('cmd.whitelist.usage'))!
				return
			}
			sender.whitelist_remove(ctx.args[1])
			sender.send_message(ctx.lang.tf('cmd.whitelist.removed', {
				'Name': ctx.args[1]
			}))!
		}
		'on' {
			sender.whitelist_set_enabled(true)
			sender.send_message(ctx.lang.t('cmd.whitelist.enabled'))!
		}
		'off' {
			sender.whitelist_set_enabled(false)
			sender.send_message(ctx.lang.t('cmd.whitelist.disabled'))!
		}
		'list' {
			names := sender.whitelist_names()
			if names.len == 0 {
				sender.send_message(ctx.lang.t('cmd.whitelist.list_empty'))!
				return
			}
			sender.send_message(names.join(', '))!
		}
		else {
			sender.send_message(ctx.lang.t('cmd.whitelist.usage'))!
		}
	}
}
