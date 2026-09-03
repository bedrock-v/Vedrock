module default

import strconv
import server.permission
import server.cmd

pub struct XpCommand {}

pub fn (c XpCommand) name() string {
	return 'xp'
}

pub fn (c XpCommand) description() string {
	return 'Gives experience points or levels to a player'
}

pub fn (c XpCommand) aliases() []string {
	return ['experience']
}

pub fn (c XpCommand) permission() string {
	return permission.command_xp
}

pub fn (c XpCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name: 'amount'
		},
		cmd.StringArgument{
			arg_name:     'player'
			arg_optional: true
		},
	]
}

// execute reads the vanilla amount form: a plain number is points, and an "L"
// suffix means levels.
pub fn (c XpCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	amount, levels := parse_xp_amount(ctx.args[0]) or {
		sender.send_message(ctx.lang.t('cmd.xp.usage'))!
		return
	}
	mut target := sender
	if ctx.args.len > 1 {
		target_name := ctx.args[1]
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
	if levels {
		target.give_experience_levels(amount)
	} else {
		target.give_experience(amount)
	}
	key := if levels { 'cmd.xp.success_levels' } else { 'cmd.xp.success' }
	sender.send_message(ctx.lang.tf(key, {
		'Amount': amount.str()
		'Name':   target.name()
	}))!
}

// parse_xp_amount splits "30L" into 30 levels and "30" into 30 points.
fn parse_xp_amount(raw string) ?(int, bool) {
	trimmed := raw.trim_space()
	if trimmed == '' {
		return none
	}
	levels := trimmed.to_upper().ends_with('L')
	digits := if levels { trimmed[..trimmed.len - 1] } else { trimmed }
	amount := strconv.atoi(digits) or { return none }
	return amount, levels
}
