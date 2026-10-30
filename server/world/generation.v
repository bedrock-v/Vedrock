module world

import server.world.chunk

// generation_queue is how many chunks may wait for a generation worker.
const generation_queue = 4096

// generate_loop fills the chunks the world asks for until the world closes.
fn (mut wr Runtime) generate_loop() {
	for {
		pos := <-wr.jobs or { return }
		if wr.closed.load() != 0 {
			continue
		}
		mut c := chunk.new()
		wr.generator.generate_chunk(pos, mut c)
		encoded := c.encode()
		wr.submit('world.chunk_generated', fn [pos, c, encoded] (mut tx Tx) {
			tx.chunk_generated(pos, c, encoded)
		}) or {}
	}
}

// request_chunk asks for a chunk the world doesn't have and reports whether
// it will come.
fn (mut tx Tx) request_chunk(pos chunk.Pos, l &Loader) bool {
	key := column_key(pos)
	if mut waiting := tx.world.requests[key] {
		waiting << l
		tx.world.requests[key] = waiting
		return true
	}
	select {
		tx.world.jobs <- pos {}
		else {
			return false
		}
	}
	tx.world.requests[key] = [l]
	return true
}

// chunk_generated stores a chunk a worker filled and hands it to every loader
// that asked for it.
fn (mut tx Tx) chunk_generated(pos chunk.Pos, c chunk.Chunk, encoded []u8) {
	key := column_key(pos)
	waiters := tx.world.requests[key] or { []&Loader{} }
	tx.world.requests.delete(key)
	mut col := tx.world.chunks[key] or {
		fresh := &Column{
			chunk:   c
			encoded: encoded
		}
		tx.world.chunks[key] = fresh
		fresh
	}
	for waiter in waiters {
		mut l := unsafe { waiter }
		l.receive(pos, mut col)
	}
}
