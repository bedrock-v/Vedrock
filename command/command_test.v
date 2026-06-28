module command

fn base_ctx() Context {
	return Context{
		sender_name:  'Steve'
		player_count: 3
		max_players:  20
		server_motd:  'Vedrock Server'
	}
}

fn test_version_command() {
	r := new_registry()
	out := r.dispatch('/version', base_ctx())
	assert out.contains('Vedrock')
	assert out.contains('1.26.30')
	assert out.contains('1001')
}

fn test_version_alias() {
	r := new_registry()
	out := r.dispatch('/ver', base_ctx())
	assert out.contains('Vedrock')
}

fn test_status_command() {
	r := new_registry()
	out := r.dispatch('status', base_ctx())
	assert out.contains('3')
	assert out.contains('20')
	assert out.contains('Vedrock Server')
}

fn test_unknown_command() {
	r := new_registry()
	out := r.dispatch('/nope', base_ctx())
	assert out.contains('Unknown command')
}

fn test_resolve_missing() {
	r := new_registry()
	if _ := r.resolve('ghost') {
		assert false
	}
}
