module session

import server.effect
import server.entity
import server.worldrt

// Effects live on player.Player. What is left here is the way into them: a
// command or an item is handled on the session thread, which holds no
// transaction. Each entry point submits a task that enters the owning
// world's actor and calls the verb there.

// PlayerAddEffectTask/PlayerRemoveEffectTask are add_effect()/remove_effect()
// run through the owning world's actor. epoch is checked via
// player_for_epoch so a stale request (submitted before a world switch)
// produces zero side effects, same as the block-write tasks.
struct PlayerAddEffectTask {
	id entity.ActorId
	effect     effect.Effect
}

fn (t PlayerAddEffectTask) name() string {
	return 'PlayerAddEffectTask'
}

fn (t PlayerAddEffectTask) run(mut tx worldrt.WorldTx) {
	mut s := player_for_id(mut tx, t.id) or { return }
	s.player.add_effect(mut tx, t.effect)
}

struct PlayerRemoveEffectTask {
	id entity.ActorId
	typ        effect.Type
}

fn (t PlayerRemoveEffectTask) name() string {
	return 'PlayerRemoveEffectTask'
}

fn (t PlayerRemoveEffectTask) run(mut tx worldrt.WorldTx) {
	mut s := player_for_id(mut tx, t.id) or { return }
	s.player.remove_effect(mut tx, t.typ)
}

fn (mut s NetworkSession) add_effect(e effect.Effect) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerAddEffectTask{
		id:     s.actor_id()
		effect: e
	})
}

fn (mut s NetworkSession) remove_effect(typ effect.Type) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerRemoveEffectTask{
		id:  s.actor_id()
		typ: typ
	})
}
