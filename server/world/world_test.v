module world

import sync
import sync.stdatomic
import time
import server.world.chunk

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
	})
	{
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
	})
	{
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
	})
	{
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

fn wait_for_count(mut wr Runtime, want int) bool {
	for _ in 0 .. 200 {
		got := call[int](mut wr, 'test.count', fn (mut tx Tx) !int {
			return tx.count()
		}) or { return false }
		if got == want {
			return true
		}
		time.sleep(time.millisecond)
	}
	return false
}

fn test_transfer_from_inside_a_transaction_moves_the_entity() {
	mut a := start('a')
	mut b := start('b')
	defer {
		a.close()
		b.close()
	}

	h := spawn_dummy(mut a, 1)
	r := ref[Dummy](h)
	call_ref[Dummy, bool](r, 'test.mark', fn (mut tx Tx, e &Dummy) !bool {
		mut d := unsafe { e }
		d.ticks = 17
		d.note = 'carried'
		return true
	})!

	call[bool](mut a, 'test.portal', fn [b] (mut tx Tx) !bool {
		tx.transfer(1, b)
		tx.entity(1) or { return error('the entity left during the callback') }
		return true
	})!

	assert wait_for_count(mut b, 1), 'the entity never arrived in b'
	assert wait_for_count(mut a, 0), 'the entity is still in a'

	note := call_ref[Dummy, string](r, 'test.read', fn (mut tx Tx, e &Dummy) !string {
		return '${tx.world_name()}:${e.ticks}:${e.note}'
	})!
	assert note == 'b:17:carried'
}

fn test_transfer_ref_moves_the_entity_and_reports_it() {
	mut a := start('a')
	mut b := start('b')
	defer {
		a.close()
		b.close()
	}

	h := spawn_dummy(mut a, 2)
	r := ref[Dummy](h)
	transfer_ref[Dummy](r, b)!

	assert call[int](mut b, 'test.count_b', fn (mut tx Tx) !int {
		return tx.count()
	})! == 1
	assert call[int](mut a, 'test.count_a', fn (mut tx Tx) !int {
		return tx.count()
	})! == 0
	where := call_ref[Dummy, string](r, 'test.where', fn (mut tx Tx, e &Dummy) !string {
		return tx.world_name()
	})!
	assert where == 'b'
}

fn test_worlds_transferring_to_each_other_do_not_deadlock() {
	mut a := start('a')
	mut b := start('b')
	defer {
		a.close()
		b.close()
	}

	ha := spawn_dummy(mut a, 10)
	hb := spawn_dummy(mut b, 20)

	t1 := spawn fn [mut a, b, ha] () {
		call[bool](mut a, 'test.send_a', fn [b] (mut tx Tx) !bool {
			tx.transfer(10, b)
			return true
		}) or { panic(err) }
		_ := ha
	}()
	t2 := spawn fn [mut b, a, hb] () {
		call[bool](mut b, 'test.send_b', fn [a] (mut tx Tx) !bool {
			tx.transfer(20, a)
			return true
		}) or { panic(err) }
		_ := hb
	}()
	t1.wait()
	t2.wait()

	assert wait_for_count(mut a, 1), "a never received b's entity"
	assert wait_for_count(mut b, 1), "b never received a's entity"
	held_by_a := call[u64](mut a, 'test.who_a', fn (mut tx Tx) !u64 {
		e := tx.entity(20) or { return error('a does not hold 20') }
		return e.id()
	})!
	assert held_by_a == 20
}

fn test_a_transfer_to_a_closed_world_returns_the_entity() {
	mut a := start('a')
	mut b := start('b')
	defer {
		a.close()
	}
	b.close()

	h := spawn_dummy(mut a, 4)
	r := ref[Dummy](h)

	if _ := transfer_ref[Dummy](r, b) {
		assert false, 'a transfer into a closed world reported success'
	}
	assert wait_for_count(mut a, 1), 'the entity did not come back to a'
	where := call_ref[Dummy, string](r, 'test.where', fn (mut tx Tx, e &Dummy) !string {
		return tx.world_name()
	})!
	assert where == 'a'
}

fn test_transfer_to_the_same_world_is_a_no_op() {
	mut a := start('a')
	defer {
		a.close()
	}

	h := spawn_dummy(mut a, 6)
	r := ref[Dummy](h)
	transfer_ref[Dummy](r, a)!

	assert call[int](mut a, 'test.count', fn (mut tx Tx) !int {
		return tx.count()
	})! == 1
}

// Ticked is an entity that counts its ticks and remembers the thread it was
// ticked on.
struct Ticked {
	id_ u64
mut:
	ticks     int
	last      i64
	ticked_on u64
}

fn (t &Ticked) id() u64 {
	return t.id_
}

fn (mut t Ticked) tick(mut tx Tx, current i64) {
	t.ticks++
	t.last = current
	t.ticked_on = sync.thread_id()
}

fn spawn_ticked(mut wr Runtime, id u64) &Handle {
	h := new_handle(id, &Ticked{
		id_: id
	})
	call[bool](mut wr, 'test.add', fn [h] (mut tx Tx) !bool {
		tx.add(h)
		return true
	}) or { panic(err) }
	return h
}

fn test_a_tick_reaches_the_entities_that_tick() {
	mut wr := start_manual('overworld')
	defer {
		wr.close()
	}
	h := spawn_ticked(mut wr, 1)
	r := ref[Ticked](h)

	before := call[i64](mut wr, 'test.tick_no', fn (mut tx Tx) !i64 {
		return tx.current_tick()
	})!
	wr.advance_tick()!

	state := call_ref[Ticked, string](r, 'test.state', fn (mut tx Tx, e &Ticked) !string {
		return '${e.ticks}:${e.last == tx.current_tick()}'
	})!
	assert state == '1:true'
	after := call[i64](mut wr, 'test.tick_no', fn (mut tx Tx) !i64 {
		return tx.current_tick()
	})!
	assert after == before + 1

	on := call_ref[Ticked, u64](r, 'test.thread', fn (mut tx Tx, e &Ticked) !u64 {
		return e.ticked_on
	})!
	assert on != sync.thread_id()
}

fn test_an_entity_that_does_not_tick_is_left_alone() {
	mut wr := start_manual('overworld')
	defer {
		wr.close()
	}
	spawn_dummy(mut wr, 2)
	wr.advance_tick()!
	assert call[int](mut wr, 'test.count', fn (mut tx Tx) !int {
		return tx.count()
	})! == 1
}

fn test_a_world_ticks_by_itself() {
	mut wr := start('overworld')
	defer {
		wr.close()
	}
	time.sleep(250 * time.millisecond)
	ticks := call[i64](mut wr, 'test.tick_no', fn (mut tx Tx) !i64 {
		return tx.current_tick()
	})!

	assert ticks >= 2, 'the world ticked ${ticks} times in 250ms'
	assert ticks <= 10, 'the world ticked ${ticks} times in 250ms'
}

fn test_missed_ticks_are_dropped_not_owed() {
	mut wr := start('overworld')
	defer {
		wr.close()
	}

	call[bool](mut wr, 'test.slow', fn (mut tx Tx) !bool {
		time.sleep(300 * time.millisecond)
		return true
	})!
	after_slow := call[i64](mut wr, 'test.tick_no', fn (mut tx Tx) !i64 {
		return tx.current_tick()
	})!
	time.sleep(100 * time.millisecond)
	later := call[i64](mut wr, 'test.tick_no', fn (mut tx Tx) !i64 {
		return tx.current_tick()
	})!

	caught_up := later - after_slow
	assert caught_up <= 4, 'the world ran ${caught_up} ticks in 100ms, so missed ticks were owed'
}

// Remover takes another entity out of the world when it ticks.
struct Remover {
	id_    u64
	target u64
}

fn (r &Remover) id() u64 {
	return r.id_
}

fn (mut r Remover) tick(mut tx Tx, current i64) {
	tx.remove(r.target) or { return }
}

fn test_an_entity_removed_during_a_tick_is_not_ticked() {
	mut wr := start_manual('overworld')
	defer {
		wr.close()
	}

	remover := new_handle(1, &Remover{
		id_:    1
		target: 2
	})
	call[bool](mut wr, 'test.add', fn [remover] (mut tx Tx) !bool {
		tx.add(remover)
		return true
	})!
	victim := spawn_ticked(mut wr, 2)
	r := ref[Ticked](victim)

	wr.advance_tick()!

	e := victim.entity
	if e is Ticked {
		assert e.ticks == 0, 'an entity removed during the tick was ticked ${e.ticks} time(s)'
	} else {
		assert false, 'the handle lost the entity'
	}
	if _ := call_ref[Ticked, int](r, 'test.reach', fn (mut tx Tx, e &Ticked) !int {
		return 1
	})
	{
		assert false, 'the removed entity is still in the world'
	}
}

// CountingGenerator counts the chunks it was asked to fill and spawns players
// somewhere a default generator wouldn't.
struct CountingGenerator {
	generated &stdatomic.AtomicVal[int] = stdatomic.new_atomic[int](0)
}

fn (g CountingGenerator) generate_chunk(pos chunk.Pos, mut c chunk.Chunk) {
	mut generated := g.generated
	generated.add(1)
}

fn (g CountingGenerator) default_spawn() BlockPos {
	return BlockPos{8, 64, -8}
}

fn collect(mut wr Runtime, mut l Loader, want int) []LoadedChunk {
	mut got := []LoadedChunk{}
	for _ in 0 .. 200 {
		got << call[[]LoadedChunk](mut wr, 'load', fn [mut l] (mut tx Tx) ![]LoadedChunk {
			return l.load(mut tx, 100)
		}) or { panic(err) }
		if got.len >= want {
			break
		}
		time.sleep(10 * time.millisecond)
	}
	return got
}

fn test_chunk_two_loaders_ask_for_is_generated_once_and_shared() {
	g := CountingGenerator{}
	mut wr := start_manual('overworld', generator: g)
	defer {
		wr.close()
	}
	mut a := new_loader(0)
	mut b := new_loader(0)
	call[bool](mut wr, 'ask', fn [mut a, mut b] (mut tx Tx) !bool {
		a.move(mut tx, 16, 32)
		b.move(mut tx, 16, 32)
		a.load(mut tx, 1)
		b.load(mut tx, 1)
		return true
	})!
	got_a := collect(mut wr, mut a, 1)
	got_b := collect(mut wr, mut b, 1)
	assert got_a.len == 1 && got_b.len == 1, 'a loader never got its chunk'
	assert got_a[0].pos == chunk.Pos{1, 2}
	assert got_a[0].encoded.data == got_b[0].encoded.data, 'the two loaders got separate copies'
	assert g.generated.load() == 1, 'the generator was asked ${g.generated.load()} times for one chunk'
}

// GatedGenerator holds every chunk until the test opens the gate.
struct GatedGenerator {
	gate chan bool = chan bool{}
}

fn (g GatedGenerator) generate_chunk(pos chunk.Pos, mut c chunk.Chunk) {
	_ := <-g.gate or { false }
}

fn (g GatedGenerator) default_spawn() BlockPos {
	return BlockPos{}
}

fn test_a_slow_generator_does_not_hold_up_the_world() {
	g := GatedGenerator{}
	mut wr := start_manual('overworld', generator: g)
	defer {
		g.gate.close()
		wr.close()
	}
	mut l := new_loader(0)
	call[bool](mut wr, 'ask', fn [mut l] (mut tx Tx) !bool {
		l.move(mut tx, 0, 0)
		l.load(mut tx, 1)
		return true
	})!
	started := time.now()
	for _ in 0 .. 5 {
		wr.advance_tick()!
	}
	assert time.since(started) < time.second, 'the world waited for the generator'

	g.gate.close()
	assert collect(mut wr, mut l, 1).len == 1, 'the chunk never arrived'
}

fn test_a_chunk_the_full_queue_turns_down_is_asked_for_again() {
	g := GatedGenerator{}
	mut wr := start_runtime('overworld', Config{
		generator: g
	}, 1)
	defer {
		g.gate.close()
		wr.close()
	}
	mut l := new_loader(1)
	counts := call[[]int](mut wr, 'ask', fn [mut l] (mut tx Tx) ![]int {
		l.move(mut tx, 0, 0)
		l.load(mut tx, 5)
		return [l.pending.len, l.queue.len]
	})!
	pending, queued := counts[0], counts[1]
	assert pending < 5, 'a queue with room for one took ${pending} chunks'
	assert pending + queued == 5, 'a chunk turned down was lost'

	g.gate.close()
	assert collect(mut wr, mut l, 5).len == 5, 'the chunks turned down were never asked for again'
}

fn test_a_chunk_that_left_the_radius_frees_its_request() {
	g := GatedGenerator{}
	mut wr := start_manual('overworld', generator: g)
	defer {
		g.gate.close()
		wr.close()
	}
	mut l := new_loader(0)
	asked := call[bool](mut wr, 'teleport', fn [mut l] (mut tx Tx) !bool {
		l.move(mut tx, 0, 0)
		l.load(mut tx, 1)
		// The first chunk is held at the gate. Far away, the one request the
		// loader has must go to the chunk it is in now.
		l.move(mut tx, 1600, 1600)
		l.load(mut tx, 1)
		return column_key(chunk.Pos{100, 100}) in l.pending
	})!
	assert asked, 'a chunk out of the radius held the only request'
}

fn test_a_world_spawns_players_where_its_generator_says() {
	mut wr := start('overworld', generator: CountingGenerator{})
	defer {
		wr.close()
	}
	spawn_pos := call[BlockPos](mut wr, 'spawn', fn (mut tx Tx) !BlockPos {
		return tx.spawn()
	})!
	assert spawn_pos == BlockPos{8, 64, -8}
}

fn chunk_count(mut wr Runtime) int {
	return call[int](mut wr, 'chunks', fn (mut tx Tx) !int {
		return tx.world.chunks.len
	}) or { panic(err) }
}

fn test_a_chunk_nobody_views_is_kept_until_the_sweep() {
	mut wr := start_manual('overworld', chunk_unload_interval: 3 * tick_interval)
	defer {
		wr.close()
	}
	mut viewer := new_loader(0)
	mut walker := new_loader(0)
	call[bool](mut wr, 'view', fn [mut viewer, mut walker] (mut tx Tx) !bool {
		viewer.move(mut tx, 0, 0)
		walker.move(mut tx, 100, 0)
		return true
	})!
	assert collect(mut wr, mut viewer, 1).len == 1
	assert collect(mut wr, mut walker, 1).len == 1
	call[bool](mut wr, 'walk', fn [mut walker] (mut tx Tx) !bool {
		walker.move(mut tx, 200, 0)
		return true
	})!
	assert chunk_count(mut wr) == 2

	wr.advance_tick()!
	wr.advance_tick()!
	assert chunk_count(mut wr) == 2, 'a chunk was dropped before the sweep'
	wr.advance_tick()!
	assert chunk_count(mut wr) == 1, 'the sweep kept a chunk nobody views or dropped a viewed one'
	kept := call[bool](mut wr, 'kept', fn (mut tx Tx) !bool {
		return column_key(chunk.Pos{0, 0}) in tx.world.chunks
	})!
	assert kept, 'the sweep dropped the chunk still in view'
}

fn test_a_closed_loader_stops_viewing() {
	mut wr := start_manual('overworld', chunk_unload_interval: tick_interval)
	defer {
		wr.close()
	}
	mut l := new_loader(1)
	call[bool](mut wr, 'view', fn [mut l] (mut tx Tx) !bool {
		l.move(mut tx, 0, 0)
		return true
	})!
	assert collect(mut wr, mut l, 5).len == 5
	call[bool](mut wr, 'close', fn [mut l] (mut tx Tx) !bool {
		l.close(mut tx)
		return true
	})!
	wr.advance_tick()!
	assert chunk_count(mut wr) == 0
}
