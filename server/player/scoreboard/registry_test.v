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

	assert r.remove_objective('kills')? == [DisplaySlot.sidebar]
	assert r.scores('kills').len == 0
	if _ := r.display(.sidebar) {
		assert false, 'the slot still shows a removed objective'
	}
	if _ := r.remove_objective('kills') {
		assert false, 'removed an objective twice'
	}
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

fn test_display_slots_map_to_their_wire_names() {
	assert DisplaySlot.sidebar.wire_name() == 'sidebar'
	assert display_slot_from_name('BelowName')? == .belowname
	if _ := display_slot_from_name('nowhere') {
		assert false, 'an unknown slot resolved'
	}
}

fn test_an_entry_keeps_its_id_across_objectives_and_resets() {
	mut r := new_registry()
	r.add_objective(Objective{ name: 'kills' })
	r.add_objective(Objective{ name: 'deaths' })
	if _ := r.entry_id('Alex') {
		assert false, 'an entry that was never scored has an id'
	}
	r.set_score('kills', 'Alex', 1)
	id := r.entry_id('Alex')?
	r.add_score('deaths', 'Alex', 1)
	r.set_score('kills', 'Steve', 1)
	r.reset_score('', 'Alex')
	assert r.entry_id('Alex')? == id
	assert r.entry_id('Steve')? != id
}

fn test_slots_showing_lists_every_slot_an_objective_is_in() {
	mut r := new_registry()
	r.add_objective(Objective{ name: 'kills' })
	r.add_objective(Objective{ name: 'deaths' })
	r.set_display(.sidebar, 'kills')
	r.set_display(.belowname, 'kills')
	r.set_display(.list, 'deaths')
	assert r.slots_showing('kills') == [DisplaySlot.sidebar, .belowname]
	assert r.slots_showing('missing').len == 0
}
