module server

import sync
import sync.stdatomic
import time
import server.net
import server.session
import server.world

// accept_poll is how long a wait for a new connection lasts before the accept
// loop looks at whether the server is still running.
const accept_poll = 500 * time.millisecond

// Server accepts clients and hands each one a session on a world.
//
// It owns the listeners, the worlds and the identity a player is admitted
// under. Gameplay state is not its business. That belongs to the world holding
// the player.
pub struct Server {
	cfg Config
mut:
	listeners []net.Listener
	overworld &world.Runtime
	// loops is held by the accept loop of each listener. An accept loop waits for
	// the clients it accepted before it lets go and this covers every thread the
	// server started.
	loops &sync.WaitGroup = sync.new_waitgroup()
	// stopped is closed once the server is down. It is what run waits on.
	stopped chan bool                 = chan bool{}
	running &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](1)
	// next_id hands out entity ids. Players are entities and share the space.
	next_id   &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](1)
	next_conn &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](1)
	// conns holds every accepted connection, logged in or not. Shutting down
	// ends them instead of leaving their threads on a socket nobody reads.
	conns map[u64]&net.Conn
	// pending holds when each connection that has not logged in yet arrived.
	pending map[u64]time.Time
	// players is how many of them were admitted. It is what max_players counts
	// and what a client is told before it joins.
	players    int
	live_mutex &sync.Mutex = sync.new_mutex()
	// announce_mutex orders what listeners are told. The count is read inside
	// it and the last announcement to run is the one that read the current
	// count.
	announce_mutex &sync.Mutex = sync.new_mutex()
}

// new binds the configured listeners and brings up the world players join.
pub fn new(cfg Config) !&Server {
	if cfg.listeners.len == 0 {
		return error('a server with no listeners would accept nobody')
	}
	status := cfg.status()
	mut listeners := []net.Listener{cap: cfg.listeners.len}
	for build in cfg.listeners {
		listeners << build(status) or {
			// The ones already bound hold ports and a server that failed to
			// start must not keep them.
			for mut bound in listeners {
				bound.close()
			}
			return err
		}
	}
	return &Server{
		cfg:       cfg
		listeners: listeners
		overworld: world.start(cfg.world_name)
	}
}

// run accepts clients until the server is closed and returns once it is down.
// Every player gets a thread of its own, reading that client's packets.
//
// The accept loops are counted under the lock close takes. A server closed
// before or during this call is one this returns from instead of starting.
pub fn (mut s Server) run() {
	s.live_mutex.lock()
	if s.running.load() == 0 {
		s.live_mutex.unlock()
		return
	}
	s.loops.add(s.listeners.len)
	s.live_mutex.unlock()
	for i in 0 .. s.listeners.len {
		spawn s.accept_loop(i)
	}
	_ := <-s.stopped or {}
}

// accept_loop takes clients from one listener. Each listener has its own and a
// client that arrives on any of them is admitted the same way.
//
// The loop owns the threads of the clients it accepted. It counts and waits for
// them itself, which is the only reason that count can't be waited on while
// another thread is still adding to it.
fn (mut s Server) accept_loop(index int) {
	mut handlers := sync.new_waitgroup()
	for s.running.load() != 0 {
		s.drop_slow_logins()
		mut listener := s.listeners[index]
		mut wire := listener.accept(accept_poll) or { continue }
		mut conn := net.new_conn(mut wire)
		cid := s.add_conn(mut conn) or {
			conn.close()
			continue
		}
		handlers.add(1)
		spawn s.admit(cid, mut conn, mut handlers)
	}
	// Their connections are closed by then, ending the reads they
	// are on.
	handlers.wait()
	s.loops.done()
}

// admit takes a client through login and runs its session.
fn (mut s Server) admit(cid u64, mut conn net.Conn, mut handlers sync.WaitGroup) {
	defer {
		s.remove_conn(cid)
		conn.close()
		handlers.done()
	}
	remote := conn.remote()
	identity := net.handshake(mut conn, s.cfg.login) or {
		// TODO There's no logger in the rewrite yet and a login that fails without
		// leaving a trace is one nobody can explain.
		eprintln('vedrock: login from ${remote} failed: ${err}')
		net.disconnect(mut conn, 'Login failed.')
		return
	}
	s.finished_login(cid)
	if !s.reserve_slot() {
		net.disconnect(mut conn, 'The server is full!')
		return
	}
	id := s.next_id.add(1)
	h := world.new_handle(id, session.new_player(id, identity.display_name))
	world.call[bool](mut s.overworld, 'server.join', fn [h] (mut tx world.Tx) !bool {
		tx.add(h)
		return true
	}) or {
		s.free_slot()
		net.disconnect(mut conn, 'The world could not take you.')
		return
	}
	mut sess := session.new_session(mut conn, h)
	sess.run()
	// The client is gone or the session gave up on it.
	world.call[bool](mut s.overworld, 'server.quit', fn [id] (mut tx world.Tx) !bool {
		tx.remove(id) or { return error('player ${id} had already left') }
		return true
	}) or {}
	s.free_slot()
}

// close stops the server in the order the parts depend on each other:
//
//  1. nothing new is accepted
//  2. every connection is dropped, ending the read its thread is on
//  3. every thread the server started is waited for
//  4. the worlds shut down, once nothing is left to ask them for anything
//
// It waits as long as that takes. A client or a world task that never finishes
// is a server that never finishes closing, the same contract the world runtime
// has.
pub fn (mut s Server) close() {
	if s.running.swap(0) == 0 {
		return
	}
	for mut listener in s.listeners {
		listener.close()
	}
	s.live_mutex.lock()
	for _, mut conn in s.conns {
		conn.close()
	}
	s.live_mutex.unlock()
	s.loops.wait()
	s.overworld.close()
	s.stopped.close()
}

// player_count is how many players are connected.
pub fn (mut s Server) player_count() int {
	s.live_mutex.lock()
	defer {
		s.live_mutex.unlock()
	}
	return s.players
}

// add_conn takes a connection the server will answer or refuses it.
fn (mut s Server) add_conn(mut conn net.Conn) ?u64 {
	s.live_mutex.lock()
	defer {
		s.live_mutex.unlock()
	}
	if s.running.load() == 0 {
		return none
	}
	if s.cfg.max_pending > 0 && s.pending.len >= s.cfg.max_pending {
		return none
	}
	cid := s.next_conn.add(1)
	s.conns[cid] = conn
	s.pending[cid] = time.now()
	return cid
}

fn (mut s Server) remove_conn(cid u64) {
	s.live_mutex.lock()
	s.conns.delete(cid)
	s.pending.delete(cid)
	s.live_mutex.unlock()
}

// finished_login frees the place this client held among the ones logging in.
fn (mut s Server) finished_login(cid u64) {
	s.live_mutex.lock()
	s.pending.delete(cid)
	s.live_mutex.unlock()
}

// drop_slow_logins ends the connections that have been logging in for longer
// than login_timeout. Closing one is what ends the read its thread is on and
// that thread takes it from there.
fn (mut s Server) drop_slow_logins() {
	now := time.now()
	s.live_mutex.lock()
	mut late := []&net.Conn{}
	for cid, since in s.pending {
		if now - since > s.cfg.login_timeout {
			if conn := s.conns[cid] {
				late << conn
			}
		}
	}
	s.live_mutex.unlock()
	for mut conn in late {
		conn.close()
	}
}

// reserve_slot takes one of the player slots or reports that there is none
// left. Taking it under the same lock that holds the count is what keeps two
// clients arriving together from both getting the last one.
fn (mut s Server) reserve_slot() bool {
	s.live_mutex.lock()
	if s.cfg.max_players > 0 && s.players >= s.cfg.max_players {
		s.live_mutex.unlock()
		return false
	}
	s.players++
	s.live_mutex.unlock()
	s.announce()
	return true
}

fn (mut s Server) free_slot() {
	s.live_mutex.lock()
	s.players--
	s.live_mutex.unlock()
	s.announce()
}

// announce tells every listener how many players are connected.
fn (mut s Server) announce() {
	s.announce_mutex.lock()
	defer {
		s.announce_mutex.unlock()
	}
	online := s.player_count()
	for mut listener in s.listeners {
		listener.announce(online)
	}
}
