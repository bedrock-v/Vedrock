module default

import server.permission
import server.cmd

// Bedrock's SetTitlePacket.type wire values, not defined in the protocol package.
const title_type_title = 2
const title_type_subtitle = 3
const title_type_actionbar = 4

pub struct TitleCommand {}

pub fn (c TitleCommand) name() string {
	return 'title'
}

pub fn (c TitleCommand) description() string {
	return 'Sends a title, subtitle, or action bar message to a player'
}

pub fn (c TitleCommand) aliases() []string {
	return []
}

pub fn (c TitleCommand) permission() string {
	return permission.command_title
}

pub fn (c TitleCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name: 'target'
		},
		cmd.StringEnumArgument{
			arg_name: 'kind'
			values:   ['title', 'subtitle', 'actionbar']
		},
		cmd.TextArgument{
			arg_name: 'text'
		},
	]
}

fn title_kind(raw string) ?int {
	return match raw.to_lower() {
		'title' { title_type_title }
		'subtitle' { title_type_subtitle }
		'actionbar' { title_type_actionbar }
		else { none }
	}
}

pub fn (c TitleCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if ctx.args.len < 3 {
		sender.send_message(ctx.lang.t('cmd.title.usage'))!
		return
	}
	target_name := ctx.args[0]
	kind := title_kind(ctx.args[1]) or {
		sender.send_message(ctx.lang.t('cmd.title.usage'))!
		return
	}
	text := ctx.args[2..].join(' ')
	if target_name == '@a' {
		sender.broadcast_title(kind, text)
		return
	}
	mut target := sender.find_player(target_name) or {
		sender.send_message(ctx.lang.tf('cmd.player_not_found', {
			'Name': target_name
		}))!
		return
	}
	target.show_title(kind, text)
}
