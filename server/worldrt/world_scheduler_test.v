module worldrt

struct NoopTask {}

fn (t NoopTask) run(mut tx WorldTx) {}

fn (t NoopTask) name() string {
	return 'noop'
}

fn test_a_world_scheduler_tracks_and_cancels_its_tasks() {
	mut s := new_world_scheduler()
	assert s.table.count() == 0

	handle := s.add(NoopTask{}, 5, 0, 100)
	assert s.table.count() == 1
	assert handle.work().name() == 'noop'
	assert !handle.is_repeating()

	s.cancel(handle.id())
	assert handle.is_cancelled()
	assert s.table.count() == 0
}
