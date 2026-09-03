module default

import strconv
import server.permission
import server.cmd

pub struct ScoreboardCommand {}

pub fn (c ScoreboardCommand) name() string {
	return 'scoreboard'
}

pub fn (c ScoreboardCommand) description() string {
	return 'Manages objectives, scores and teams'
}

pub fn (c ScoreboardCommand) aliases() []string {
	return []
}

pub fn (c ScoreboardCommand) permission() string {
	return permission.command_scoreboard
}

pub fn (c ScoreboardCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name: 'section'
		},
		cmd.StringArgument{
			arg_name:     'action'
			arg_optional: true
		},
		cmd.StringArgument{
			arg_name:     'a'
			arg_optional: true
		},
		cmd.StringArgument{
			arg_name:     'b'
			arg_optional: true
		},
		cmd.StringArgument{
			arg_name:     'c'
			arg_optional: true
		},
	]
}

pub fn (c ScoreboardCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	match ctx.args[0].to_lower() {
		'objectives' { run_objectives(mut sender, ctx)! }
		'players' { run_players(mut sender, ctx)! }
		'teams' { run_teams(mut sender, ctx)! }
		else { sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))! }
	}
}

fn run_objectives(mut sender cmd.Sender, ctx cmd.Context) ! {
	action := if ctx.args.len > 1 { ctx.args[1].to_lower() } else { '' }
	match action {
		'add' {
			if ctx.args.len < 3 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			name := ctx.args[2]
			display := if ctx.args.len > 3 { ctx.args[3] } else { '' }
			if !sender.scoreboard_add_objective(name, display) {
				sender.send_message(ctx.lang.t('cmd.scoreboard.objective_exists'))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.objectives.add', {
				'Objective': name
			}))!
		}
		'remove' {
			if ctx.args.len < 3 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			name := ctx.args[2]
			if !sender.scoreboard_remove_objective(name) {
				sender.send_message(ctx.lang.tf('cmd.scoreboard.objective_not_found', {
					'Objective': name
				}))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.objectives.remove', {
				'Objective': name
			}))!
		}
		'list' {
			objectives := sender.scoreboard_objectives()
			if objectives.len == 0 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.objectives.list_empty'))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.objectives.list', {
				'Count': objectives.len.str()
			}))!
			for objective in objectives {
				sender.send_message('- ${objective.name}: ${objective.display_name}')!
			}
		}
		'setdisplay' {
			if ctx.args.len < 3 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			slot := ctx.args[2]
			objective := if ctx.args.len > 3 { ctx.args[3] } else { '' }
			if !sender.scoreboard_set_display(slot, objective) {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			if objective == '' {
				sender.send_message(ctx.lang.tf('cmd.scoreboard.setdisplay.cleared', {
					'Slot': slot
				}))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.setdisplay.success', {
				'Slot':      slot
				'Objective': objective
			}))!
		}
		else {
			sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
		}
	}
}

fn run_players(mut sender cmd.Sender, ctx cmd.Context) ! {
	action := if ctx.args.len > 1 { ctx.args[1].to_lower() } else { '' }
	if action == 'reset' {
		if ctx.args.len < 3 {
			sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
			return
		}
		entry := ctx.args[2]
		sender.scoreboard_reset_score(entry)
		sender.send_message(ctx.lang.tf('cmd.scoreboard.players.reset', {
			'Name': entry
		}))!
		return
	}
	if action != 'set' && action != 'add' {
		sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
		return
	}
	if ctx.args.len < 5 {
		sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
		return
	}
	entry := ctx.args[2]
	objective := ctx.args[3]
	amount := strconv.atoi(ctx.args[4]) or {
		sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
		return
	}
	if action == 'set' {
		if !sender.scoreboard_set_score(objective, entry, amount) {
			sender.send_message(ctx.lang.tf('cmd.scoreboard.objective_not_found', {
				'Objective': objective
			}))!
			return
		}
		sender.send_message(ctx.lang.tf('cmd.scoreboard.players.set', {
			'Objective': objective
			'Name':      entry
			'Score':     amount.str()
		}))!
		return
	}
	updated := sender.scoreboard_add_score(objective, entry, amount) or {
		sender.send_message(ctx.lang.tf('cmd.scoreboard.objective_not_found', {
			'Objective': objective
		}))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.scoreboard.players.add', {
		'Amount':    amount.str()
		'Objective': objective
		'Name':      entry
		'Score':     updated.str()
	}))!
}

fn run_teams(mut sender cmd.Sender, ctx cmd.Context) ! {
	action := if ctx.args.len > 1 { ctx.args[1].to_lower() } else { '' }
	match action {
		'add' {
			if ctx.args.len < 3 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			name := ctx.args[2]
			display := if ctx.args.len > 3 { ctx.args[3] } else { '' }
			if !sender.scoreboard_add_team(name, display) {
				sender.send_message(ctx.lang.t('cmd.scoreboard.team_exists'))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.teams.add', {
				'Team': name
			}))!
		}
		'remove' {
			if ctx.args.len < 3 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			name := ctx.args[2]
			if !sender.scoreboard_remove_team(name) {
				sender.send_message(ctx.lang.tf('cmd.scoreboard.team_not_found', {
					'Team': name
				}))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.teams.remove', {
				'Team': name
			}))!
		}
		'join' {
			if ctx.args.len < 4 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			team := ctx.args[2]
			entry := ctx.args[3]
			if !sender.scoreboard_team_join(team, entry) {
				sender.send_message(ctx.lang.tf('cmd.scoreboard.team_not_found', {
					'Team': team
				}))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.teams.join', {
				'Name': entry
				'Team': team
			}))!
		}
		'leave' {
			if ctx.args.len < 3 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			entry := ctx.args[2]
			if !sender.scoreboard_team_leave(entry) {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.teams.leave', {
				'Name': entry
			}))!
		}
		'option' {
			if ctx.args.len < 5 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
				return
			}
			team := ctx.args[2]
			option := ctx.args[3]
			value := ctx.args[4]
			if !sender.scoreboard_team_option(team, option, value) {
				sender.send_message(ctx.lang.tf('cmd.scoreboard.team_not_found', {
					'Team': team
				}))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.teams.option', {
				'Option': option
				'Team':   team
				'Value':  value
			}))!
		}
		'list' {
			teams := sender.scoreboard_teams()
			if teams.len == 0 {
				sender.send_message(ctx.lang.t('cmd.scoreboard.teams.list_empty'))!
				return
			}
			sender.send_message(ctx.lang.tf('cmd.scoreboard.teams.list', {
				'Count': teams.len.str()
			}))!
			for team in teams {
				sender.send_message('- ${team.name}: ${team.display_name} (${team.members})')!
			}
		}
		else {
			sender.send_message(ctx.lang.t('cmd.scoreboard.usage'))!
		}
	}
}
