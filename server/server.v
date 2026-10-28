module server

import rand
import sync
import sync.stdatomic
import time
import server.network
import server.session
import server.world
import server.world.chunk

// accept_poll is how long a wait for a logged-in client lasts before the
// accept loop looks at whether the server is still running.
const accept_poll = 500 * time.millisecond

// Server accepts clients and hands each one a session on a world.
//
// It owns the listeners, the worlds and the identity a player is admitted
// under. Gameplay state is not its business. That belongs to the world holding
// the player.
pub struct Server {
	cfg Config
mut:
	// logins take each listener's clients through logging in, one per listener.
	logins []&network.LoginHandler
	// listener_context holds what the listeners share: the media port's mux and
	// the player slots.
	listener_context &network.ListenerContext
	// verifier is the login verifier the server built itself, which it closes.
	// One passed in Config is the caller's.
	verifier  ?&network.OidcVerifier
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
	// conns holds every client handed over by a login. Shutting down ends them
	// instead of leaving their threads on a socket nobody reads.
	conns map[u64]&network.Conn
	// online holds the UUID of every player that has spawned and not left, hence
	// one account is in once.
	online     map[string]bool
	live_mutex &sync.Mutex = sync.new_mutex()
}

// new binds the configured listeners and brings up the world players join.
pub fn new(cfg Config) !&Server {
	if cfg.listeners.len == 0 {
		return error('a server with no listeners would accept nobody')
	}
	mut status := cfg.status()
	if status.network_id == 0 {
		status = network.Status{
			...status
			network_id: rand.u64()
		}
	}
	mut verifier := cfg.verifier
	mut owned := ?&network.OidcVerifier(none)
	if verifier == none && !cfg.login.allow_unverified {
		built := network.OidcVerifier.new() or {
			return error('logins can not be verified: ${err}')
		}
		owned = built
		verifier = built
	}
	mut ctx := &network.ListenerContext{
		status:     status
		media_port: cfg.media_port
		verifier:   verifier
	}
	mut listeners := []network.Listener{cap: cfg.listeners.len}
	for build in cfg.listeners {
		listeners << build(mut ctx) or {
			// The ones already bound hold ports and a server that failed to
			// start must not keep them.
			for mut bound in listeners {
				bound.close()
			}
			ctx.close()
			if mut built := owned {
				built.close()
			}
			return err
		}
	}
	mut logins := []&network.LoginHandler{cap: listeners.len}
	for listener in listeners {
		logins << network.LoginHandler.new(listener, mut ctx, cfg.login)
	}
	return &Server{
		cfg:              cfg
		logins:           logins
		listener_context: ctx
		verifier:         owned
		overworld:        world.start(cfg.world_name, generator: cfg.generator)
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
	s.loops.add(s.logins.len)
	s.live_mutex.unlock()
	for i in 0 .. s.logins.len {
		spawn s.accept_loop(i)
	}
	_ := <-s.stopped or {}
}

// accept_loop takes the clients one listener's logins hand over. Each listener
// has its own and a client that arrives on any of them joins the same way.
//
// The loop owns the threads of the clients it accepted. It counts and waits for
// them itself, which is the only reason that count can't be waited on while
// another thread is still adding to it.
fn (mut s Server) accept_loop(index int) {
	mut handlers := sync.new_waitgroup()
	for s.running.load() != 0 {
		mut login := s.logins[index]
		mut client := login.accept(accept_poll) or { continue }
		cid := s.add_conn(mut client.conn) or {
			client.conn.close()
			s.listener_context.free_slot()
			continue
		}
		handlers.add(1)
		spawn s.admit(cid, client, mut handlers)
	}
	// Their connections are closed by then, ending the reads they
	// are on.
	handlers.wait()
	s.loops.done()
}

// admit puts a logged-in client into the world and runs its session. The
// client arrives holding a player slot and gives it back when it leaves.
fn (mut s Server) admit(cid u64, client network.Client, mut handlers sync.WaitGroup) {
	mut conn := client.conn
	defer {
		s.remove_conn(cid)
		conn.close()
		s.listener_context.free_slot()
		handlers.done()
	}
	id := s.next_id.add(1)
	mut overworld := s.overworld
	arrival := world.call[world.BlockPos](mut overworld, 'server.spawn', fn (mut tx world.Tx) !world.BlockPos {
		return tx.spawn()
	}) or {
		network.disconnect(mut conn, 'The world could not take you.')
		return
	}
	network.start_game(mut conn, network.GameData{
		entity_id:  id
		world_name: s.cfg.world_name
		spawn:      [arrival.x, arrival.y, arrival.z]!
		game_type:  s.cfg.game_type
		chunks:     fn [mut overworld] (positions []chunk.Pos) ![][]u8 {
			return world.call[[][]u8](mut overworld, 'server.spawn_chunks', fn [positions] (mut tx world.Tx) ![][]u8 {
				return positions.map(tx.encoded_chunk(it))
			})
		}
	}) or {
		// TODO There's no logger in the rewrite yet.
		eprintln('vedrock: ${client.identity.display_name} did not spawn: ${err}')
		return
	}
	if !s.claim_player(client.identity.uuid) {
		network.disconnect(mut conn, 'Already logged in.')
		return
	}
	defer {
		s.release_player(client.identity.uuid)
	}
	authenticated := if client.identity.xbox_authenticated {
		'xbox authenticated'
	} else {
		'not xbox authenticated'
	}
	offer := if _ := conn.public_key() { 'signed offer' } else { 'unsigned offer' }
	// TODO Yeah, I know what to do... A LOGGEEEEEEEEEEEER
	eprintln('vedrock: ${client.identity.display_name} joined, ${authenticated}, ${offer}')
	h := world.new_handle(id, session.new_player(id, client.identity.display_name))
	world.call[bool](mut s.overworld, 'server.join', fn [h] (mut tx world.Tx) !bool {
		tx.add(h)
		return true
	}) or {
		network.disconnect(mut conn, 'The world could not take you.')
		return
	}
	mut sess := session.new_session(mut conn, h)
	sess.run()
	// The client is gone or the session gave up on it.
	world.call[bool](mut s.overworld, 'server.quit', fn [id] (mut tx world.Tx) !bool {
		tx.remove(id) or { return error('player ${id} had already left') }
		return true
	}) or {}
}

// close stops the server in the order the parts depend on each other:
//
//  1. nothing new is accepted and every login in progress is ended
//  2. every player's connection is dropped, ending the read its thread is on
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
	for mut login in s.logins {
		login.close()
	}
	s.live_mutex.lock()
	for _, mut conn in s.conns {
		conn.close()
	}
	s.live_mutex.unlock()
	s.loops.wait()
	s.listener_context.close()
	if mut verifier := s.verifier {
		verifier.close()
	}
	s.overworld.close()
	s.stopped.close()
}

// player_count is how many player slots are taken by players and by clients
// still logging in.
pub fn (mut s Server) player_count() int {
	return s.listener_context.player_count()
}

// add_conn takes a client the server will run or refuses it once the server is
// shutting down.
fn (mut s Server) add_conn(mut conn network.Conn) ?u64 {
	s.live_mutex.lock()
	defer {
		s.live_mutex.unlock()
	}
	if s.running.load() == 0 {
		return none
	}
	cid := s.next_conn.add(1)
	s.conns[cid] = conn
	return cid
}

fn (mut s Server) remove_conn(cid u64) {
	s.live_mutex.lock()
	s.conns.delete(cid)
	s.live_mutex.unlock()
}

// claim_player marks a player as in or reports that it already is. Checking
// and marking under one lock is what keeps two logins of one account arriving
// together from both getting in.
fn (mut s Server) claim_player(uuid string) bool {
	s.live_mutex.lock()
	defer {
		s.live_mutex.unlock()
	}
	if uuid in s.online {
		return false
	}
	s.online[uuid] = true
	return true
}

fn (mut s Server) release_player(uuid string) {
	s.live_mutex.lock()
	s.online.delete(uuid)
	s.live_mutex.unlock()
}
