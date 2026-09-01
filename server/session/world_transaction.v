module session

import server.event
import server.world
import server.entity
import bedrock_v.protocol.types

// WorldTransaction is the public transaction surface passed to World.exec.
// Its operations run on the owning world thread, allowing several reads
// and mutations to execute in order without additional queue round trips.
pub interface WorldTransaction {
	block_at(x int, y int, z int) world.Block
mut:
	set_block(x int, y int, z int, b world.Block) !
	players() []PlayerRef
	spawn_entity(config EntityConfig) !EntityRef
}

// EntityConfig identifies a registered entity type and its spawn position.
// Entities are created through the registry by name rather than from
// caller provided Behaviour instances.
pub struct EntityConfig {
pub:
	type_name string
	pos       types.Vector3
}

// WorldTxHandle adapts the internal WorldTx to the public
// WorldTransaction interface.
struct WorldTxHandle {
mut:
	tx &WorldTx
}

// block_at reads the block at the given coordinates, resolved against this
// transaction's own in progress writes.
pub fn (h &WorldTxHandle) block_at(x int, y int, z int) world.Block {
	return world.block_from_id(block_at(h.tx, x, y, z))
}

// set_block writes a block, visible to later reads in the same transaction
// and broadcast to players in this world once the transaction commits.
pub fn (mut h WorldTxHandle) set_block(x int, y int, z int, b world.Block) ! {
	h.tx.set_block(x, y, z, b.network_id)
}

// players lists every player currently registered in this world.
pub fn (mut h WorldTxHandle) players() []PlayerRef {
	mut out := []PlayerRef{}
	for mut a in h.tx.wr.entities.player_actors() {
		if mut a is NetworkSession {
			out << player_ref_for(a)
		}
	}
	return out
}

// spawn_entity validates and spawns an entity directly within the current
// world transaction, avoiding an additional task and result round trip.
pub fn (mut h WorldTxHandle) spawn_entity(config EntityConfig) !EntityRef {
	behaviour := entity.create(config.type_name) or {
		return error('unknown entity type "${config.type_name}"')
	}
	mut ctx := event.new_context(event.EntitySpawnData{
		identifier: behaviour.identifier()
		x:          config.pos.x
		y:          config.pos.y
		z:          config.pos.z
	})
	h.tx.wr.handler.on_entity_spawn(mut ctx)
	if ctx.is_cancelled() {
		return error('entity spawn was cancelled')
	}
	e := h.tx.wr.entities.spawn(behaviour, config.pos)
	return EntityRef{
		runtime_id: e.runtime_id()
		world_:     World{
			runtime: h.tx.wr
		}
	}
}

// ExecOutcome transports a transaction callback error through world_call
// which returns plain values. The caller converts it back into an error.
struct ExecOutcome {
	failed bool
	msg    string
}

// exec runs "f" as one ordered transaction on the owning world thread.
// Operations inside the callback can't interleave with other world tasks
// and callback errors are returned by exec.
//
// label identifies the transaction in WorldMetrics.longest_task_name, so a
// slow callback is attributed to the caller rather than to exec itself. An
// empty label falls back to the name of this function.
//
// Keep callbacks short, synchronous and world local: blocking work stalls the
// entire world. PlayerRef and EntityRef methods start a nested world
// transaction and panic when called from inside the callback.
//
// To return a value from the callback, use a channel. Mutable closure
// captures are copied in V and don't update the enclosing variable.
pub fn (mut w World) exec(label string, f fn (mut tx WorldTransaction) !) ! {
	task_label := if label == '' { 'World.exec' } else { label }
	outcome := world_call[ExecOutcome](task_label, mut w.runtime, fn [f] (mut tx WorldTx) ExecOutcome {
		mut handle := WorldTransaction(&WorldTxHandle{
			tx: &tx
		})
		f(mut handle) or { return ExecOutcome{
			failed: true
			msg:    err.msg()
		} }
		return ExecOutcome{}
	}) or { return error('world "${w.runtime.world.name}" is shutting down') }

	if outcome.failed {
		return error(outcome.msg)
	}
}
