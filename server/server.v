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
	// loops is held by the accept loop of each listener.
	loops &sync.WaitGroup = sync.new_waitgroup()
	// sessions is held by the thread of every accepted client from the moment
	// it is accepted until it is gone.
	sessions &sync.WaitGroup           = sync.new_waitgroup()
	running  &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](1)
	// next_id hands out entity ids. Players are entities and share the space.
	next_id   &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](1)
	next_conn &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](1)
	// conns holds every accepted connection, logged in or not. Shutting down
	// ends them instead of leaving their threads on a socket nobody reads.
	conns map[u64]&net.Conn
	// players is how many of them were admitted. It is what max_players counts
	// and what a client is told before it joins.
	players    int
	live_mutex &sync.Mutex = sync.new_mutex()
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

// run accepts clients until the server is closed. It blocks the calling thread
// and every player gets a thread of its own, reading that client's packets.
pub fn (mut s Server) run() {
	for i in 0 .. s.listeners.len {
		s.loops.add(1)
		spawn s.accept_loop(i)
	}
	s.loops.wait()
}

// accept_loop takes clients from one listener. Each listener has its own and a
// client that arrives on any of them is admitted the same way.
fn (mut s Server) accept_loop(index int) {
	defer {
		s.loops.done()
	}
	for s.running.load() != 0 {
		mut listener := s.listeners[index]
		mut wire := listener.accept(accept_poll) or { continue }
		mut conn := net.new_conn(mut wire)
		cid := s.add_conn(mut conn)
		s.sessions.add(1)
		spawn s.admit(cid, mut conn)
	}
}

// admit takes a client through login and runs its session.
fn (mut s Server) admit(cid u64, mut conn net.Conn) {
	defer {
		s.remove_conn(cid)
		conn.close()
		s.sessions.done()
	}
	remote := conn.remote()
	identity := net.handshake(mut conn, s.cfg.login) or {
		// TODO There's no logger in the rewrite yet and a login that fails without
		// leaving a trace is one nobody can explain.
		eprintln('vedrock: login from ${remote} failed: ${err}')
		net.disconnect(mut conn, 'Login failed.')
		return
	}
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

// close stops the server. No new client is accepted, every connected client is
// dropped, and the world shuts down once the work it has already taken is
// done.
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
	// A closed connection is what ends the read its thread is blocked on. The
	// world stays up until those threads are done with it.
	s.sessions.wait()
	s.overworld.close()
}

// player_count is how many players are connected.
pub fn (mut s Server) player_count() int {
	s.live_mutex.lock()
	defer {
		s.live_mutex.unlock()
	}
	return s.players
}

fn (mut s Server) add_conn(mut conn net.Conn) u64 {
	cid := s.next_conn.add(1)
	s.live_mutex.lock()
	s.conns[cid] = conn
	s.live_mutex.unlock()
	return cid
}

fn (mut s Server) remove_conn(cid u64) {
	s.live_mutex.lock()
	s.conns.delete(cid)
	s.live_mutex.unlock()
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
	count := s.players
	s.live_mutex.unlock()
	s.announce(count)
	return true
}

fn (mut s Server) free_slot() {
	s.live_mutex.lock()
	s.players--
	count := s.players
	s.live_mutex.unlock()
	s.announce(count)
}

// announce tells every listener how many players are connected.
fn (mut s Server) announce(online int) {
	for mut listener in s.listeners {
		listener.announce(online)
	}
}
