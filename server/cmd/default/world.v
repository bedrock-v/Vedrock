module default

import server.permission
import server.cmd

pub struct WorldCommand {}

pub fn (c WorldCommand) name() string {
	return 'world'
}

pub fn (c WorldCommand) description() string {
	return 'Manages worlds - list, info, create, delete, tp'
}

pub fn (c WorldCommand) aliases() []string {
	return ['worlds']
}

pub fn (c WorldCommand) permission() string {
	return permission.command_world
}

pub fn (c WorldCommand) arguments() []cmd.Argument {
	return [
		cmd.StringEnumArgument{
			arg_name: 'action'
			values:   ['list', 'info', 'create', 'delete', 'tp']
		},
		cmd.StringArgument{
			arg_name:     'name'
			arg_optional: true
		},
	]
}

pub fn (c WorldCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if ctx.args.len == 0 {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	action := ctx.args[0].to_lower()
	match action {
		'list' {
			c.list(mut sender, ctx)!
		}
		'info' {
			c.info(mut sender, ctx)!
		}
		'create' {
			c.create(mut sender, ctx)!
		}
		'delete' {
			c.delete(mut sender, ctx)!
		}
		'tp' {
			c.teleport(mut sender, ctx)!
		}
		else {
			sender.send_message(ctx.lang.t('cmd.world.usage'))!
		}
	}
}

fn (c WorldCommand) list(mut sender cmd.Sender, ctx cmd.Context) ! {
	names := sender.world_names()
	if names.len == 0 {
		sender.send_message(ctx.lang.t('cmd.world.none'))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.list', {
		'Count':  names.len.str()
		'Worlds': names.join(', ')
	}))!
}

fn (c WorldCommand) info(mut sender cmd.Sender, ctx cmd.Context) ! {
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	info := sender.world_info(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.not_found', {
			'Name': name
		}))!
		return
	}
	mut lines := []string{}
	lines << '§6World: §a${info.name}§r'
	lines << '§6Generator: §f${info.generator}§r'
	lines << '§6Block overrides: §f${info.overrides}§r'
	lines << '§6Players: §f${info.players}§r'
	lines << '§6Default: §f${info.is_default}§r'
	sender.send_message(lines.join('\n'))!
}

fn (c WorldCommand) create(mut sender cmd.Sender, ctx cmd.Context) ! {
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	sender.world_create(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.create_failed', {
			'Name':   name
			'Reason': err.msg()
		}))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.created', {
		'Name': name
	}))!
}

fn (c WorldCommand) delete(mut sender cmd.Sender, ctx cmd.Context) ! {
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	sender.world_delete(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.delete_failed', {
			'Name':   name
			'Reason': err.msg()
		}))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.deleted', {
		'Name': name
	}))!
}

fn (c WorldCommand) teleport(mut sender cmd.Sender, ctx cmd.Context) ! {
	if !sender.is_player() {
		sender.send_message(ctx.lang.t('cmd.player_only'))!
		return
	}
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	sender.world_teleport(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.tp_failed', {
			'Name':   name
			'Reason': err.msg()
		}))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.tp', {
		'Name': name
	}))!
}

// name_arg returns the second argument, or none when it's missing/blank.
fn (c WorldCommand) name_arg(ctx cmd.Context) ?string {
	if ctx.args.len < 2 || ctx.args[1].trim_space() == '' {
		return none
	}
	return ctx.args[1]
}
