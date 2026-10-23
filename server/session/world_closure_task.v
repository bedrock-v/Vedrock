module session

import server.worldrt

// WorldClosureTask runs a caller supplied closure against the public
// transaction surface. It lives here rather than with the scheduler because
// WorldTransaction is this package's API, not the actor's.
pub struct WorldClosureTask {
pub:
	callback fn (mut tx WorldTransaction) @[required]
}

fn (t WorldClosureTask) name() string {
	return 'WorldClosureTask'
}

fn (t WorldClosureTask) run(mut tx worldrt.WorldTx) {
	mut handle := WorldTransaction(&WorldTxHandle{
		tx: &tx
	})
	t.callback(mut handle)
}
