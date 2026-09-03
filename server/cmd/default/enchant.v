module default

import strconv
import server.permission
import server.cmd
import server.player

pub struct EnchantCommand {}

pub fn (c EnchantCommand) name() string {
	return 'enchant'
}

pub fn (c EnchantCommand) description() string {
	return 'Enchants the item a player is holding'
}

pub fn (c EnchantCommand) aliases() []string {
	return []
}

pub fn (c EnchantCommand) permission() string {
	return permission.command_enchant
}

pub fn (c EnchantCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name: 'player'
		},
		cmd.StringArgument{
			arg_name: 'enchantment'
		},
		cmd.IntArgument{
			arg_name:     'level'
			arg_optional: true
		},
	]
}

pub fn (c EnchantCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	target_name := ctx.args[0]
	mut target := sender.find_player(target_name) or {
		sender.send_message(ctx.lang.tf('cmd.player_not_found', {
			'Name': target_name
		}))!
		return
	}
	name := ctx.args[1].all_after('minecraft:')
	mut level := 1
	if ctx.args.len > 2 {
		level = strconv.atoi(ctx.args[2]) or {
			sender.send_message(ctx.lang.t('cmd.enchant.usage'))!
			return
		}
	}
	match target.enchant_held_item(name, level) {
		.applied {
			sender.send_message(ctx.lang.t('cmd.enchant.success'))!
		}
		.no_item {
			sender.send_message(ctx.lang.t('cmd.enchant.no_item'))!
		}
		.not_found {
			sender.send_message(ctx.lang.tf('cmd.enchant.not_found', {
				'Enchantment': name
			}))!
		}
		.cannot_combine {
			sender.send_message(ctx.lang.tf('cmd.enchant.cant_combine', {
				'Enchantment': name
				'Item':        target.held_item_name()
			}))!
		}
	}
}
