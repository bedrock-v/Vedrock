module network

import sync
import time
import bedrock_v.protocol.packets

// accept_poll is how long a wait for a new connection lasts before the accept
// loop looks at whether the handler is still open.
const accept_poll = 500 * time.millisecond

// Client is a connection that finished logging in and who it says it is.
pub struct Client {
pub:
	identity Identity
pub mut:
	conn &Conn
}

// LoginHandler takes the connections one listener accepts through the login
// sequence and hands out the ones that finish it.
//
// A client holds a player slot from the moment it arrives. One that fails, runs
// out of time or is still logging in when the handler closes gives its slot
// back. A client handed out keeps it and whoever accepted it frees it.
@[heap]
pub struct LoginHandler {
	cfg LoginConfig
mut:
	listener Listener
	ctx      &ListenerContext
	// logged_in is unbuffered, a client is handed only to an accept that
	// takes it.
	logged_in chan Client = chan Client{}
	// done is closed by close, waking whatever waits on the handler.
	done chan bool  = chan bool{}
	mu   &sync.Mutex = sync.new_mutex()
	// logins holds the connections still logging in. Close can end them.
	logins map[u64]&Conn
	// active counts the logins whose threads are running, handover included.
	active  int
	next_id u64
	closed  bool
	threads &sync.WaitGroup = sync.new_waitgroup()
}

// LoginHandler.new starts taking clients from listener. The player count it
// checks and the listeners told about it are shared through ctx.
pub fn LoginHandler.new(listener Listener, mut ctx ListenerContext, cfg LoginConfig) &LoginHandler {
	ctx.add_listener(listener)
	mut h := &LoginHandler{
		cfg:      cfg
		listener: listener
		ctx:      ctx
	}
	h.threads.add(1)
	spawn h.accept_loop()
	return h
}

// accept takes the next client that logged in, waiting up to timeout for one.
pub fn (mut h LoginHandler) accept(timeout time.Duration) !Client {
	select {
		client := <-h.logged_in {
			return client
		}
		_ := <-h.done {
			return error('the login handler is closed')
		}
		timeout {
			return error('no client logged in')
		}
	}
	return error('no client logged in')
}

// close stops taking clients, ends the logins in progress and returns once
// every thread the handler started is done. A client already handed out is not
// the handler's to end.
pub fn (mut h LoginHandler) close() {
	h.mu.lock()
	if h.closed {
		h.mu.unlock()
		return
	}
	h.closed = true
	h.done.close()
	mut logins := h.logins.values()
	h.mu.unlock()

	h.listener.close()
	for mut conn in logins {
		conn.close()
	}
	h.threads.wait()
}

fn (mut h LoginHandler) is_closed() bool {
	h.mu.lock()
	defer {
		h.mu.unlock()
	}
	return h.closed
}

// accept_loop takes connections off the listener and starts each one's login.
fn (mut h LoginHandler) accept_loop() {
	defer {
		h.threads.done()
	}
	for !h.is_closed() {
		mut wire := h.listener.accept(accept_poll) or { continue }
		mut conn := new_conn(mut wire)
		if h.at_capacity() {
			conn.close()
			continue
		}
		if !h.ctx.reserve_slot() {
			conn.write(&packets.PlayStatusPacket{
				status: .login_failed_server_full_sub_client
			}) or {}
			conn.close()
			continue
		}
		h.mu.lock()
		if h.closed {
			h.mu.unlock()
			conn.close()
			h.ctx.free_slot()
			return
		}
		h.next_id++
		id := h.next_id
		h.logins[id] = conn
		h.active++
		h.threads.add(1)
		h.mu.unlock()
		spawn h.login(id, mut conn)
	}
}

// at_capacity reports whether as many logins as max_concurrent are running.
// Only accept_loop starts one and nothing can start another between this check
// and the start.
fn (mut h LoginHandler) at_capacity() bool {
	if h.cfg.max_concurrent <= 0 {
		return false
	}
	h.mu.lock()
	defer {
		h.mu.unlock()
	}
	return h.active >= h.cfg.max_concurrent
}

// login takes one client through the sequence and hands it out.
fn (mut h LoginHandler) login(id u64, mut conn Conn) {
	defer {
		h.mu.lock()
		h.active--
		h.mu.unlock()
		h.threads.done()
	}
	remote := conn.remote()
	identity := h.attempt(mut conn) or {
		closing := !h.forget(id)
		if !closing {
			// TODO There's no logger in the rewrite yet and a login that fails
			// without leaving a trace is one nobody can explain.
			eprintln('vedrock: login from ${remote} failed: ${err}')
		}
		if err is VersionMismatch {
			conn.close()
		} else {
			disconnect(mut conn, 'Login failed.')
		}
		h.ctx.free_slot()
		return
	}
	if !h.forget(id) {
		// close took the connection while it finished and has closed it.
		h.ctx.free_slot()
		return
	}
	select {
		h.logged_in <- Client{
			identity: identity
			conn:     conn
		} {}
		_ := <-h.done {
			conn.close()
			h.ctx.free_slot()
		}
	}
}

// forget takes a connection off the ones logging in. It reports false once the
// handler is closing when close has the connection.
fn (mut h LoginHandler) forget(id u64) bool {
	h.mu.lock()
	defer {
		h.mu.unlock()
	}
	h.logins.delete(id)
	return !h.closed
}

// attempt runs the sequence on its own thread and closes the connection if the
// deadline passes first which ends any read it is blocked on. Only this thread
// decides whether the client made it in time. One finishing just as the deadline
// fires may still be refused since select can pick either.
fn (mut h LoginHandler) attempt(mut conn Conn) !Identity {
	if h.cfg.timeout <= 0 {
		return handshake(mut conn, h.cfg)!
	}
	finished := chan bool{cap: 1}
	sequence := spawn run_handshake(mut conn, h.cfg, finished)
	deadline := h.cfg.timeout
	select {
		_ := <-finished {}
		deadline {
			conn.close()
			sequence.wait() or {}
			return error('did not log in within ${deadline}')
		}
	}
	identity := sequence.wait()!
	return identity
}

fn run_handshake(mut conn Conn, cfg LoginConfig, finished chan bool) !Identity {
	defer {
		finished <- true
	}
	return handshake(mut conn, cfg)!
}
