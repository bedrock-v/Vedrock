module scoreboard

fn test_an_objective_is_registered_once() {
	mut r := new_registry()
	assert r.add_objective(Objective{ name: 'kills' })
	assert !r.add_objective(Objective{ name: 'kills' })
	assert r.objectives().len == 1
	if _ := r.objective('kills') {
	} else {
		assert false, 'objective was not stored'
	}
}

fn test_removing_an_objective_takes_its_scores_and_display_with_it() {
	mut r := new_registry()
	r.add_objective(Objective{ name: 'kills' })
	r.set_score('kills', 'Alex', 4)
	r.set_display(.sidebar, 'kills')

	assert r.remove_objective('kills')
	assert r.scores('kills').len == 0
	if _ := r.display(.sidebar) {
		assert false, 'the slot still shows a removed objective'
	}
	assert !r.remove_objective('kills')
}

fn test_scores_only_exist_under_a_known_objective() {
	mut r := new_registry()
	assert !r.set_score('missing', 'Alex', 1)
	if _ := r.add_score('missing', 'Alex', 1) {
		assert false, 'scored against an objective that does not exist'
	}
	r.add_objective(Objective{ name: 'kills' })
	assert r.set_score('kills', 'Alex', 2)
	assert r.add_score('kills', 'Alex', 3)? == 5
	assert r.scores('kills')['Alex'] == 5
}

fn test_resetting_a_score_clears_every_objective() {
	mut r := new_registry()
	r.add_objective(Objective{ name: 'kills' })
	r.add_objective(Objective{ name: 'deaths' })
	r.set_score('kills', 'Alex', 1)
	r.set_score('deaths', 'Alex', 2)
	r.set_score('kills', 'Steve', 3)

	r.reset_score('', 'Alex')
	assert 'Alex' !in r.scores('kills')
	assert 'Alex' !in r.scores('deaths')
	assert r.scores('kills')['Steve'] == 3
}

fn test_a_slot_only_shows_a_known_objective() {
	mut r := new_registry()
	assert !r.set_display(.sidebar, 'missing')
	r.add_objective(Objective{ name: 'kills' })
	assert r.set_display(.sidebar, 'kills')
	assert r.display(.sidebar)? == 'kills'
	// An empty name clears the slot.
	assert r.set_display(.sidebar, '')
	if _ := r.display(.sidebar) {
		assert false, 'the slot was not cleared'
	}
}

fn test_membership_moves_between_teams() {
	mut r := new_registry()
	r.add_team(Team{ name: 'red' })
	r.add_team(Team{ name: 'blue' })
	assert r.join_team('red', 'Alex')
	assert r.team_of('Alex')?.name == 'red'

	assert r.join_team('blue', 'Alex')
	assert r.team_of('Alex')?.name == 'blue'
	assert r.members('red').len == 0
	assert r.members('blue') == ['Alex']

	assert r.leave_team('Alex')
	assert !r.leave_team('Alex')
	if _ := r.team_of('Alex') {
		assert false, 'Alex is still on a team'
	}
}

fn test_removing_a_team_empties_it() {
	mut r := new_registry()
	r.add_team(Team{ name: 'red' })
	r.join_team('red', 'Alex')
	assert r.remove_team('red')
	if _ := r.team_of('Alex') {
		assert false, 'Alex kept a team that no longer exists'
	}
	assert !r.remove_team('red')
}

fn test_same_team_needs_both_to_be_on_one() {
	mut r := new_registry()
	r.add_team(Team{ name: 'red' })
	r.join_team('red', 'Alex')
	assert !r.same_team('Alex', 'Steve')
	r.join_team('red', 'Steve')
	assert r.same_team('Alex', 'Steve')
	// Two players in no team are not teammates.
	assert !r.same_team('Nobody', 'Nobody else')
}

fn test_a_team_decorates_its_members_names() {
	team := Team{
		name:   'red'
		colour: 'c'
		prefix: '[R] '
	}
	assert team.decorate('Alex') == '§c[R] Alex§r'
	plain := Team{
		name: 'plain'
	}
	assert plain.decorate('Alex') == 'Alex'
}

fn test_display_slots_map_to_their_wire_names() {
	assert DisplaySlot.sidebar.wire_name() == 'sidebar'
	assert display_slot_from_name('BelowName')? == .belowname
	if _ := display_slot_from_name('nowhere') {
		assert false, 'an unknown slot resolved'
	}
}
