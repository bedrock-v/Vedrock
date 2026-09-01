module session

import sync
import time
import bedrock_v.protocol.types
import server.internal.gamedata
import server.internal.logger
import server.player
import server.world
import server.world.db
import bedrock_v.protocol.current as proto

struct BlockingGenerator {
	started chan bool
	release chan bool
	claim   chan bool
	inner   world.Generator = world.VoidGenerator{}
}

fn new_blocking_generator(started chan bool, release chan bool) BlockingGenerator {
	claim := chan bool{cap: 1}
	claim <- true
	return BlockingGenerator{
		started: started
		release: release
		claim:   claim
	}
}

fn (g BlockingGenerator) spawn_y() int {
	return g.inner.spawn_y()
}

fn (g BlockingGenerator) uses_blocks() bool {
	return g.inner.uses_blocks()
}

fn (g BlockingGenerator) block_at(x int, y int, z int) int {
	return g.inner.block_at(x, y, z)
}

fn (g BlockingGenerator) biome_at(x int, z int) int {
	return g.inner.biome_at(x, z)
}

fn (g BlockingGenerator) generate(chunk_x int, chunk_z int) world.Chunk {
	mut claimed := false
	select {
		_ := <-g.claim {
			claimed = true
		}
		else {}
	}
	if claimed {
		select {
			g.started <- true {}
			else {}
		}
		_ := <-g.release
	}
	return g.inner.generate(chunk_x, chunk_z)
}

fn register_blocking_generator(mut hub Hub, name string, gen BlockingGenerator) {
	hub.register_generator(name, fn [gen] (dim world.Dimension) world.Generator {
		return gen
	})
}

fn chunk_stream_test_session(mut hub Hub, mut wr WorldRuntime, gen world.Generator, mut transport FakeTransport) &NetworkSession {
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		spawned:       true
		conn: &Conn{ transport: transport }
		world:         wr.world
		world_runtime: wr
		generator:     gen
		view_radius:   2
		last_chunk_x:  100
		last_chunk_z:  100
		log:           logger.new(.info)
	}
	s.player.reset_position(types.Vector3{0, 0, 0})
	world_call[bool]('test', mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn actor_is_responsive(mut wr WorldRuntime, timeout_ms int) bool {
	done := chan bool{cap: 1}
	spawn fn [mut wr, done] () {
		world_call[bool]('test', mut wr, fn (mut tx WorldTx) bool {
			return true
		}) or {}
		done <- true
	}()
	mut responded := false
	select {
		_ := <-done {
			responded = true
		}
		timeout_ms * time.millisecond {
			responded = false
		}
	}
	return responded
}

fn wait_for_chunk_packet(transport &FakeTransport, timeout_ms int) bool {
	deadline := time.now().add(timeout_ms * time.millisecond)
	for time.now() < deadline {
		for p in transport.sent {
			if p is proto.LevelChunkPacket {
				return true
			}
		}
		select {
			_ := <-transport.sent_notify {}
			50 * time.millisecond {}
		}
	}
	for p in transport.sent {
		if p is proto.LevelChunkPacket {
			return true
		}
	}
	return false
}

fn test_chunk_streaming_doesnt_block_the_world_actor() {
	mut hub := new_hub(gamedata.GameData{})
	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	gen := new_blocking_generator(started, release)
	register_blocking_generator(mut hub, 'blocking-chunk-stream', gen)
	w := db.new_world('chunk-stream', none, 'blocking-chunk-stream', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('chunk-stream') or { panic('expected chunk-stream runtime') }
	defer {
		hub.close_worlds()
	}

	mut transport := &FakeTransport{}
	mut s := chunk_stream_test_session(mut hub, mut wr, gen, mut transport)

	s.stream_chunks_if_moved()
	_ := <-started // generation is now blocked on its own thread, not the actor

	assert actor_is_responsive(mut wr, 2000)

	release <- true
	assert wait_for_chunk_packet(transport, 2000)
}

fn test_chunk_delivery_dropped_after_a_world_switch() {
	mut hub := new_hub(gamedata.GameData{})
	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	gen := new_blocking_generator(started, release)
	register_blocking_generator(mut hub, 'blocking-chunk-switch-a', gen)
	world_a := db.new_world('chunk-switch-a', none, 'blocking-chunk-switch-a', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('chunk-switch-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('chunk-switch-a') or { panic('expected world a runtime') }
	mut wr_b := hub.world_runtime('chunk-switch-b') or { panic('expected world b runtime') }
	defer {
		hub.close_worlds()
	}

	mut transport := &FakeTransport{}
	mut s := chunk_stream_test_session(mut hub, mut wr_a, gen, mut transport)

	s.stream_chunks_if_moved()
	_ := <-started // generation for world a is now blocked on its own thread

	// Mirror change_world's real sequence: deregister from the source world,
	// rebind, then register with the destination.
	world_call[bool]('test', mut wr_a, fn [s] (mut tx WorldTx) bool {
		tx.deregister_player(s.runtime_id)
		return true
	}) or { panic('deregistration rejected - world unexpectedly stopped') }
	gen_b := world_b.make_generator(hub.build_generator(world_b))
	s.set_world_binding(wr_b, gen_b)
	world_call[bool]('test', mut wr_b, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	release <- true // let the batch generated for world a finish

	time.sleep(300 * time.millisecond) // bounded window for a wrongly delivered batch to show up
	for p in transport.sent {
		assert p !is proto.LevelChunkPacket
	}
}

struct ConcurrencyTracker {
mut:
	mutex     &sync.Mutex = sync.new_mutex()
	in_flight int
	peak      int
}

fn (mut t ConcurrencyTracker) enter() {
	t.mutex.lock()
	t.in_flight++
	if t.in_flight > t.peak {
		t.peak = t.in_flight
	}
	t.mutex.unlock()
}

fn (mut t ConcurrencyTracker) leave() {
	t.mutex.lock()
	t.in_flight--
	t.mutex.unlock()
}

struct ConcurrentBlockingGenerator {
	tracker &ConcurrencyTracker
	release chan bool
	inner   world.Generator = world.VoidGenerator{}
}

fn (g ConcurrentBlockingGenerator) spawn_y() int {
	return g.inner.spawn_y()
}

fn (g ConcurrentBlockingGenerator) uses_blocks() bool {
	return g.inner.uses_blocks()
}

fn (g ConcurrentBlockingGenerator) block_at(x int, y int, z int) int {
	return g.inner.block_at(x, y, z)
}

fn (g ConcurrentBlockingGenerator) biome_at(x int, z int) int {
	return g.inner.biome_at(x, z)
}

fn (g ConcurrentBlockingGenerator) generate(chunk_x int, chunk_z int) world.Chunk {
	mut tracker := g.tracker
	tracker.enter()
	_ := <-g.release
	tracker.leave()
	return g.inner.generate(chunk_x, chunk_z)
}

fn test_req_chunk_chans_keeps_worker_pool_busy_concurrently() {
	mut hub := new_hub(gamedata.GameData{})
	mut tracker := &ConcurrencyTracker{
		mutex: sync.new_mutex()
	}
	release := chan bool{cap: 512}
	gen := ConcurrentBlockingGenerator{
		tracker: tracker
		release: release
	}
	hub.register_generator('concurrent-blocking-stream', fn [gen] (dim world.Dimension) world.Generator {
		return gen
	})
	w := db.new_world('chunk-concurrency', none, 'concurrent-blocking-stream', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('chunk-concurrency') or {
		panic('expected chunk-concurrency runtime')
	}
	defer {
		hub.close_worlds()
	}

	mut transport := &FakeTransport{}
	mut s := chunk_stream_test_session(mut hub, mut wr, gen, mut transport)

	mut targets := []ChunkSendTarget{cap: 20}
	for i in 0 .. 20 {
		targets << ChunkSendTarget{
			x: i
			z: 0
		}
	}
	mut pipeline := s.new_chunk_pipeline(wr, targets)

	deadline := time.now().add(2000 * time.millisecond)
	for time.now() < deadline {
		tracker.mutex.lock()
		reached := tracker.in_flight >= chunk_gen_worker_count
		tracker.mutex.unlock()
		if reached {
			break
		}
		time.sleep(5 * time.millisecond)
	}
	tracker.mutex.lock()
	peak := tracker.peak
	tracker.mutex.unlock()
	assert peak == chunk_gen_worker_count, 'expected all ${chunk_gen_worker_count} workers busy at once from one session-style request burst, got peak ${peak}'

	for _ in 0 .. 20 {
		release <- true
	}
	mut drained := 0
	for {
		_, _ := pipeline.next_result() or { break }
		drained++
	}
	assert drained == targets.len
}

fn test_chunk_columns_are_released_when_delivery_is_dropped() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('chunk-drop', none, 'void', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('chunk-drop') or { panic('expected chunk-drop runtime') }

	mut transport := &FakeTransport{}
	mut s := chunk_stream_test_session(mut hub, mut wr, world.VoidGenerator{}, mut transport)

	// A stopped runtime rejects every delivery task, which is the same outcome
	// as a full queue: nothing reaches the client.
	hub.close_worlds()
	s.stream_chunks_if_moved()

	deadline := time.now().add(2000 * time.millisecond)
	for time.now() < deadline {
		s.chunk_stream_mutex.lock()
		remaining := s.sent_chunks.len
		s.chunk_stream_mutex.unlock()
		if remaining == 0 {
			break
		}
		time.sleep(10 * time.millisecond)
	}
	s.chunk_stream_mutex.lock()
	remaining := s.sent_chunks.len
	s.chunk_stream_mutex.unlock()
	assert remaining == 0, 'undelivered columns stayed claimed and would never be resent'
}
