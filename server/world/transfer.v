module world

// Moving an entity between worlds takes two transactions: one on the source to
// take it out, one on the destination to put it in. Its Handle carries its
// state in between.

// transfer moves an entity into another world. Use it from inside a
// transaction such as when a player walks into a portal.
//
// The entity leaves once the current callback returns. Work still reading it
// finishes first and it arrives on a thread of its own. While it is in neither
// world a Ref to it fails. A destination that refuses it sends it home.
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
// The two transactions run one after the other and the entity has arrived by
// the time it returns.
//
// It fails if the entity is in no world, if either world is closed, or if it
// has since left the world its reference pointed at. A destination that refuses
// it sends it home and the caller is told why.
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
