module session

import time
import bedrock_v.protocol
import server.internal.encryption
import server.internal.gamedata
import server.internal.auth
import server.internal.logger
import server.entity
import server.player
import server.world
import server.world.db
import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import server.worldrt

struct MetricsBarrierTask {
	started chan bool
	release chan bool
}

fn (t MetricsBarrierTask) name() string {
	return 'MetricsBarrierTask'
}

fn (t MetricsBarrierTask) run(mut tx worldrt.WorldTx) {
	t.started <- true
	_ := <-t.release
}

// MetricsFillerTask does nothing, used purely to occupy queue slots.
struct MetricsFillerTask {}

fn (t MetricsFillerTask) name() string {
	return 'MetricsFillerTask'
}

fn (t MetricsFillerTask) run(mut tx worldrt.WorldTx) {}

// SlowMetricsTask sleeps for delay_ms so it shows up as the longest task by
// a wide, non flaky margin against whatever else ran alongside it.
struct SlowMetricsTask {
	delay_ms int
}

fn (t SlowMetricsTask) name() string {
	return 'SlowMetricsTask'
}

fn (t SlowMetricsTask) run(mut tx worldrt.WorldTx) {
	time.sleep(t.delay_ms * time.millisecond)
}

fn metrics_test_world_runtime() (&Hub, &worldrt.WorldRuntime) {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('metrics-test', none, 'flat', world.overworld)
	hub.add_world(w)
	wr := hub.world_runtime('metrics-test') or { panic('expected metrics-test runtime') }
	return hub, wr
}

fn metrics_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

fn test_metrics_reports_queued_work_while_world_is_stalled() {
	mut hub, mut wr := metrics_test_world_runtime()
	defer {
		hub.close_worlds()
	}

	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	assert wr.submit(MetricsBarrierTask{
		started: started
		release: release
	})
	_ := <-started // actor is now provably stuck, before anything else is queued

	for _ in 0 .. 3 {
		assert wr.try_submit(MetricsFillerTask{})
	}

	// metrics() must answer correctly while the actor is still stuck, that
	// is the whole reason it doesn't go through worldrt.world_call.
	m := wr.metrics()
	assert m.queued_tasks == 3
	assert m.oldest_queued_task_age > 0

	release <- true
	assert metrics_wait_until(2000, fn [mut wr] () bool {
		return wr.metrics().queued_tasks == 0
	})
}

fn test_metrics_reports_longest_task_name() {
	mut hub, mut wr := metrics_test_world_runtime()
	defer {
		hub.close_worlds()
	}

	assert wr.submit(SlowMetricsTask{
		delay_ms: 40
	})
	assert wr.submit(MetricsFillerTask{})

	worldrt.world_call[bool]('test', mut wr, fn (mut tx worldrt.WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected - world unexpectedly stopped') }

	m := wr.metrics()
	assert m.longest_task_name == 'SlowMetricsTask'
	assert m.longest_task_duration >= 30 * time.millisecond
}

fn test_metrics_reports_player_and_entity_counts() {
	mut hub, mut wr := metrics_test_world_runtime()
	defer {
		hub.close_worlds()
	}

	mut transport := &FakeTransport{}
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Steve'
	}
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		conn: &Conn{ transport: transport }
		hub:           hub
		world:         wr.world
		world_runtime: wr
		generator:     world.VoidGenerator{}
		log:           logger.new(.info)
	}
	hub.add(s)
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:cow'
	}, types.Vector3{})

	ground_truth_players := worldrt.world_call[int]('test', mut wr, fn (mut tx worldrt.WorldTx) int {
		return int(tx.wr.entities.player_actor_count())
	}) or { panic('read rejected - world unexpectedly stopped') }

	m := wr.metrics()
	assert m.player_count == i64(ground_truth_players)
	assert m.entity_count == wr.entities.count()
	assert m.entity_count == 1
}

fn test_metrics_reports_catchup_events_and_tick_overruns_on_a_large_debt() {
	mut hub, mut wr := metrics_test_world_runtime()
	defer {
		hub.close_worlds()
	}

	wr.request_tick(500)
	assert metrics_wait_until(2000, fn [wr] () bool {
		return wr.tick_snapshot() == worldrt.max_world_catchup_ticks
	})

	m := wr.metrics()
	assert m.catchup_events == 1
	assert m.tick_overruns == 1
	assert m.current_tick == worldrt.max_world_catchup_ticks
	assert m.requested_tick == 500
	assert m.simulation_debt_ticks == 500 - worldrt.max_world_catchup_ticks
}

fn test_metrics_reports_scheduled_backlog() {
	mut hub, mut wr := metrics_test_world_runtime()
	defer {
		hub.close_worlds()
	}

	assert wr.metrics().scheduled_backlog == 0

	worldrt.world_call[bool]('test', mut wr, fn (mut tx worldrt.WorldTx) bool {
		// Far enough out that no amount of ticking in this test reaches it.
		tx.wr.world.schedule_tick(0, 60, 0, 100000)
		return true
	}) or { panic('schedule rejected - world unexpectedly stopped') }

	assert wr.metrics().scheduled_backlog == 1
}

fn test_metrics_liquid_backlog_matches_actor_owned_state_after_a_tick() {
	mut hub, mut wr := metrics_test_world_runtime()
	defer {
		hub.close_worlds()
	}

	assert wr.submit(PlaceWaterTask{
		x: 0
		y: 60
		z: 0
	})
	worldrt.world_call[bool]('test', mut wr, fn (mut tx worldrt.WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected - world unexpectedly stopped') }

	wr.request_tick(1)
	assert metrics_wait_until(2000, fn [wr] () bool {
		return wr.tick_runs_count() > 0
	})

	ground_truth_backlog := worldrt.world_call[int]('test', mut wr, fn (mut tx worldrt.WorldTx) int {
		return tx.wr.liquids.pending_count()
	}) or { panic('read rejected - world unexpectedly stopped') }

	assert wr.metrics().liquid_backlog == ground_truth_backlog
}

@[heap]
struct StallingTransport {
mut:
	blocked chan bool = chan bool{cap: 1}
	started chan bool = chan bool{cap: 1}
}

fn (mut t StallingTransport) wait_started() {
	_ := <-t.started
}

fn (mut t StallingTransport) send(p protocol.Packet) ! {
	select {
		t.started <- true {}
		else {}
	}
	_ := <-t.blocked
}

fn (mut t StallingTransport) send_batch(packets []protocol.Packet) ! {
	_ := <-t.blocked
}

fn (mut t StallingTransport) read() ![]protocol.Packet {
	return []protocol.Packet{}
}

fn (t &StallingTransport) remote_addr() string {
	return 'stalling:0'
}

fn (mut t StallingTransport) close() {
	select {
		t.blocked <- true {}
		else {}
	}
}

fn (mut t StallingTransport) mark_logged_in() {}

fn (mut t StallingTransport) enable_compression(threshold int) {}

fn (mut t StallingTransport) enable_encryption(mut ctx encryption.Context) {}

fn (t &StallingTransport) disable_encryption() bool {
	return false
}

fn test_metrics_tracks_outbound_overflow_and_peak_depth() {
	mut hub, mut wr := metrics_test_world_runtime()
	defer {
		hub.close_worlds()
	}

	mut transport := &StallingTransport{}
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		conn: &Conn{ transport: transport }
		hub:           hub
		world:         wr.world
		world_runtime: wr
		generator:     world.VoidGenerator{}
		log:           logger.new(.info)
	}
	hub.add(s)
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	assert wr.metrics().outbound_overflow_count == 0

	// Deliver one packet and wait for the writer to actually be blocked
	// inside send() before filling the queue, so the fill loop below always
	// lands exactly at capacity regardless of thread scheduling.
	s.deliver(&proto.TextPacket{})
	transport.wait_started()

	for _ in 0 .. outbound_queue_capacity {
		s.deliver(&proto.TextPacket{})
	}
	assert wr.metrics().outbound_overflow_count == 0

	s.deliver(&proto.TextPacket{}) // one past capacity, this overflows

	assert wr.metrics().outbound_overflow_count == 1
	assert wr.metrics().outbound_peak_depth == 0 // no tick has sampled it yet

	wr.request_tick(1)
	assert metrics_wait_until(2000, fn [wr] () bool {
		return wr.tick_runs_count() > 0
	})
	assert wr.metrics().outbound_peak_depth >= 200
}
