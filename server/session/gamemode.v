module session

import protocol
import server.event

fn gamemode_id(name string) int {
	return match name.to_lower() {
		'survival' { protocol.game_type_survival }
		'adventure' { protocol.game_type_adventure }
		'spectator' { protocol.game_type_spectator }
		else { protocol.game_type_creative }
	}
}

// PlayerSetGamemodeTask is set_gamemode() run through the owning world's
// actor. epoch is checked via player_for_epoch so a stale request (e.g. an
// /gamemode command submitted just before a world switch) produces zero
// side effects.
struct PlayerSetGamemodeTask {
	runtime_id u64
	epoch      i64
	mode       int
}

fn (t PlayerSetGamemodeTask) run(mut tx WorldTx) {
	mut s := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	s.apply_gamemode(mut tx.wr.events, t.mode)
}

fn (mut s NetworkSession) set_gamemode(mode int) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerSetGamemodeTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
		mode:       mode
	})
}

// apply_gamemode is the actual mutation, run exclusively on the owning
// world's actor via PlayerSetGamemodeTask above.
fn (mut s NetworkSession) apply_gamemode(mut events event.Bus, mode int) {
	mut ctx := event.new_context(event.GameModeChangeData{
		player: s
		mode:   mode
	})
	events.gamemode_change(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	s.player.set_game_mode(ctx.val.mode)
	s.deliver(&protocol.SetPlayerGameTypePacket{
		gamemode: s.player.game_mode()
	})
	s.deliver(&protocol.UpdateAbilitiesPacket{
		data: s.build_abilities()
	})
}
