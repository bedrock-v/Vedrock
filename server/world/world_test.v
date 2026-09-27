module world

import sync

// A test entity. Nothing about it is guarded.
struct Dummy {
	id_ u64
mut:
	ticks int
	note  string
}

fn (d &Dummy) id() u64 {
	return d.id_
}

fn spawn_dummy(mut wr Runtime, id u64) &Handle {
	h := new_handle(id, &Dummy{
		id_: id
	})
	call[bool](mut wr, 'test.add', fn [h] (mut tx Tx) !bool {
		tx.add(h)
		return true
	}) or { panic(err) }
	return h
}

fn test_work_runs_on_the_actor_thread() {
	mut wr := start('overworld')
	defer {
		wr.close()
	}

	caller := sync.thread_id()
	ran_on := call[u64](mut wr, 'test.thread', fn (mut tx Tx) !u64 {
		return sync.thread_id()
	}) or { panic(err) }
	assert ran_on != caller
	assert ran_on != 0
}

fn test_a_transaction_reaches_only_its_own_world() {
	mut a := start('a')
	mut b := start('b')
	defer {
		a.close()
		b.close()
	}

	h := spawn_dummy(mut a, 1)
	r := ref[Dummy](h)

	found_in_a := call[bool](mut a, 'test.in_a', fn [r] (mut tx Tx) !bool {
		r.get(&tx) or { return error('not in this world') }
		return true
	}) or { panic(err) }
	assert found_in_a

	if _ := call[bool](mut b, 'test.in_b', fn [r] (mut tx Tx) !bool {
		r.get(&tx) or { return error('not in this world') }
		return true
	}) {
		assert false, 'the entity resolved in a world that does not hold it'
	}
	assert call[int](mut b, 'test.count', fn (mut tx Tx) !int {
		return tx.count()
	})! == 0
}

fn test_a_reference_follows_the_entity() {
	mut a := start('a')
	mut b := start('b')
	defer {
		a.close()
		b.close()
	}

	h := spawn_dummy(mut a, 7)
	r := ref[Dummy](h)

	call[bool](mut a, 'test.remove', fn (mut tx Tx) !bool {
		tx.remove(7) or { return error('a does not hold 7') }
		return true
	}) or { panic(err) }
	call[bool](mut b, 'test.add', fn [h] (mut tx Tx) !bool {
		tx.add(h)
		return true
	}) or { panic(err) }

	where := call_ref[Dummy, string](r, 'test.where', fn (mut tx Tx, e &Dummy) !string {
		return tx.world_name()
	}) or { panic(err) }
	assert where == 'b'
	assert call[int](mut a, 'test.count_a', fn (mut tx Tx) !int {
		return tx.count()
	})! == 0
}

fn test_a_reference_to_a_worldless_entity_fails() {
	mut wr := start('overworld')
	defer {
		wr.close()
	}

	h := spawn_dummy(mut wr, 3)
	r := ref[Dummy](h)
	call[bool](mut wr, 'test.remove', fn (mut tx Tx) !bool {
		tx.remove(3) or { return error('the world does not hold 3') }
		return true
	}) or { panic(err) }

	if _ := call_ref[Dummy, int](r, 'test.orphan', fn (mut tx Tx, e &Dummy) !int {
		return 1
	}) {
		assert false, 'work ran against an entity that is in no world'
	}
}

fn test_deferred_work_runs_in_order_after_the_callback() {
	mut wr := start('overworld')
	defer {
		wr.close()
	}

	h := spawn_dummy(mut wr, 5)
	r := ref[Dummy](h)

	order := call[string](mut wr, 'test.defer', fn [r] (mut tx Tx) !string {
		mut d := r.get(&tx) or { return error('the entity is not here') }
		d.note += 'callback'
		tx.defer(fn [r] (mut tx Tx) {
			mut e := r.get(&tx) or { return }
			e.note += ' first'
		})
		tx.defer(fn [r] (mut tx Tx) {
			mut e := r.get(&tx) or { return }
			e.note += ' second'
		})
		return d.note
	}) or { panic(err) }
	assert order == 'callback'

	note := call_ref[Dummy, string](r, 'test.read', fn (mut tx Tx, e &Dummy) !string {
		return e.note
	}) or { panic(err) }
	assert note == 'callback first second'
}

fn test_concurrent_callers_do_not_lose_updates() {
	mut wr := start('overworld')
	defer {
		wr.close()
	}

	h := spawn_dummy(mut wr, 9)
	r := ref[Dummy](h)

	mut threads := []thread{}
	for _ in 0 .. 8 {
		threads << spawn fn [mut wr, r] () {
			for _ in 0 .. 50 {
				call[bool](mut wr, 'test.tick', fn [r] (mut tx Tx) !bool {
					mut d := r.get(&tx) or { return error('the entity is not here') }
					d.ticks++
					return true
				}) or { panic(err) }
			}
		}()
	}
	threads.wait()

	ticks := call_ref[Dummy, int](r, 'test.ticks', fn (mut tx Tx, e &Dummy) !int {
		return e.ticks
	}) or { panic(err) }
	assert ticks == 400
}

fn test_a_closed_world_refuses_work() {
	mut wr := start('overworld')
	wr.close()

	if _ := call[int](mut wr, 'test.after_close', fn (mut tx Tx) !int {
		return 1
	}) {
		assert false, 'a closed world ran work'
	}
	wr.submit('test.after_close', fn (mut tx Tx) {}) or { return }
	assert false, 'a closed world accepted work'
}

fn test_closing_twice_is_harmless() {
	mut wr := start('overworld')
	wr.close()
	wr.close()
}

fn test_work_queued_before_close_still_runs() {
	mut wr := start('overworld')
	h := spawn_dummy(mut wr, 11)
	r := ref[Dummy](h)

	for _ in 0 .. 20 {
		wr.submit('test.tick', fn [r] (mut tx Tx) {
			mut d := r.get(&tx) or { return }
			d.ticks++
		}) or { panic(err) }
	}
	wr.close()

	assert h.id() == 11
	mut ran := 0
	e := h.entity
	if e is Dummy {
		ran = e.ticks
	}
	assert ran == 20, 'only ${ran} of 20 queued tasks ran before close'
}

fn test_closing_while_callers_submit_does_not_crash() {
	mut wr := start('overworld')
	mut threads := []thread{}
	for _ in 0 .. 4 {
		threads << spawn fn [mut wr] () {
			for _ in 0 .. 200 {
				wr.submit('test.noop', fn (mut tx Tx) {}) or { return }
			}
		}()
	}
	wr.close()
	threads.wait()
}
