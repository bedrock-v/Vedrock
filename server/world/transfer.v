module world

// Moving an entity between worlds is two transactions: it leaves in
// a transaction on the source and joins in one on the destination. The Handle
// carries its state in between.

// transfer moves the entity into another world for callers already holding a
// transaction.
//
// It leaves once the callback returns and work still reading it is not cut off
// halfway. It arrives on its own thread. In between it is in no world and a Ref
// to it fails. A destination that will not take it sends it home.
pub fn (mut tx Tx) transfer(id u64, dst &Runtime) {
	tx.defer(fn [id, dst] (mut tx Tx) {
		src := tx.world
		h := tx.remove(id) or { return }
		spawn fn [h, dst, src] () {
			mut d := unsafe { dst }
			d.submit('world.transfer', fn [h] (mut tx Tx) {
				tx.add(h)
			}) or {
				mut s := unsafe { src }
				s.submit('world.transfer.return', fn [h] (mut tx Tx) {
					tx.add(h)
				}) or {}
			}
		}()
	})
}

// transfer_ref moves an entity to another world from outside any transaction.
//
// It fails if the entity is in no world, if either world is closed, or if it has
// since left the world its reference pointed at. An entity the destination will
// not take goes home and the caller still hears why.
pub fn transfer_ref[T](r Ref[T], dst &Runtime) ! {
	mut src := r.handle.world
	if isnil(src) {
		return error('entity ${r.id()} is in no world')
	}
	mut d := unsafe { dst }
	if src == d {
		return
	}
	h := call[&Handle](mut src, 'world.take', fn [r] [T](mut tx Tx) !&Handle {
		return tx.remove(r.id()) or {
			error('entity ${r.id()} is no longer in world "${tx.world_name()}"')
		}
	})!
	call[bool](mut d, 'world.place', fn [h] (mut tx Tx) !bool {
		tx.add(h)
		return true
	}) or {
		// The entity has already left the source. Put it back rather than
		// leaving it belonging to no world and report what went wrong.
		call[bool](mut src, 'world.place.return', fn [h] (mut tx Tx) !bool {
			tx.add(h)
			return true
		}) or {
			return error('entity ${r.id()} could not enter world "${d.name()}" (${err}) and world "${src.name()}" would not take it back')
		}
		return err
	}
}
