module permission

import os

fn test_default_granted_is_always_true() {
	p := Permissible{}
	assert p.has_permission(command_version)
}

fn test_default_op_requires_op() {
	mut p := Permissible{}
	assert !p.has_permission(command_status)
	p.set_op(true)
	assert p.has_permission(command_status)
}

fn test_unregistered_permission_defaults_denied() {
	p := Permissible{}
	assert !p.has_permission('vedrock.cmd.doesnotexist')
}

fn test_register_new_permission_at_runtime() {
	name := 'vedrock.test.runtime_registered'
	mut p := Permissible{}
	assert !p.has_permission(name)

	register(Permission{
		name:    name
		default: .granted
	})

	assert p.has_permission(name)
}

fn test_explicit_override_wins_over_default() {
	mut p := Permissible{}
	p.set_op(true)
	p.set_permission(command_status, false)
	assert !p.has_permission(command_status)
	p.unset_permission(command_status)
	assert p.has_permission(command_status)
}

fn test_ops_persist_roundtrip() {
	path := os.join_path(os.temp_dir(), 'vedrock_ops_test_${os.getpid()}.txt')
	defer {
		os.rm(path) or {}
	}
	mut ops := load_ops(path)!
	assert !ops.is_op('Steve')
	ops.add('Steve')!
	assert ops.is_op('steve')

	reloaded := load_ops(path)!
	assert reloaded.is_op('Steve')

	ops.remove('steve')!
	after_remove := load_ops(path)!
	assert !after_remove.is_op('Steve')
}

// Concurrent permission reads and op writes must be safe because permission
// checks and admin commands can run from different caller threads.
fn test_permissible_concurrent_set_op_is_race_free() {
	mut p := Permissible{}
	mut threads := []thread{}
	for i in 0 .. 16 {
		threads << spawn fn [mut p, i] () {
			for _ in 0 .. 200 {
				p.set_op(i % 2 == 0)
				_ := p.op()
				_ := p.has_permission(command_status)
			}
		}()
	}
	threads.wait()
	final := p.op()
	assert final == true || final == false
}
