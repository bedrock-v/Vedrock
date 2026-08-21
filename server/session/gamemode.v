module session

import server.event
import protocol.current as proto

fn gamemode_id(name string) int {
	return match name.to_lower() {
		'survival' { proto.game_type_survival }
		'adventure' { proto.game_type_adventure }
		'spectator' { proto.game_type_spectator }
		else { proto.game_type_creative }
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

fn (t PlayerSetGamemodeTask) name() string {
	return 'PlayerSetGamemodeTask'
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
	s.deliver(&proto.SetPlayerGameTypePacket{
		player_game_type: proto.game_type(s.player.game_mode())
	})
	s.deliver(&proto.UpdateAbilitiesPacket{
		data: s.build_abilities()
	})
}
