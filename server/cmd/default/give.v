module default

import strconv
import server.permission
import server.cmd

pub struct GiveCommand {}

pub fn (c GiveCommand) name() string {
	return 'give'
}

pub fn (c GiveCommand) description() string {
	return 'Gives an item to a player'
}

pub fn (c GiveCommand) aliases() []string {
	return []
}

pub fn (c GiveCommand) permission() string {
	return permission.command_give
}

pub fn (c GiveCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name: 'player'
		},
		cmd.StringArgument{
			arg_name: 'item'
		},
		cmd.IntArgument{
			arg_name:     'count'
			arg_optional: true
		},
	]
}

pub fn (c GiveCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	target_name := ctx.args[0]
	mut target := sender.find_player(target_name) or {
		sender.send_message(ctx.lang.tf('cmd.player_not_found', {
			'Name': target_name
		}))!
		return
	}
	mut item_id := ctx.args[1]
	if !item_id.contains(':') {
		item_id = 'minecraft:${item_id}'
	}
	mut count := 1
	if ctx.args.len > 2 {
		count = strconv.atoi(ctx.args[2]) or {
			sender.send_message(ctx.lang.t('cmd.give.usage'))!
			return
		}
	}
	if count < 1 {
		count = 1
	}
	if !target.give_item(item_id, count) {
		sender.send_message(ctx.lang.tf('cmd.give.unknown_item', {
			'Item': item_id
		}))!
		return
	}
	target.send_message(ctx.lang.tf('cmd.give.received', {
		'Count': count.str()
		'Item':  item_id
	}))!
	sender.send_message(ctx.lang.tf('cmd.give.success', {
		'Count': count.str()
		'Item':  item_id
		'Name':  target.name()
	}))!
}
