module session

import protocol.version.v662.packets as packets_662
import protocol.version.v776.packets as packets_776
import server.event
import server.internal.network

fn gamemode_id(name string) int {
	return match name.to_lower() {
		'survival' { network.game_type_survival }
		'adventure' { network.game_type_adventure }
		'spectator' { network.game_type_spectator }
		else { network.game_type_creative }
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
	s.deliver(&packets_662.SetPlayerGameTypePacket{
		player_game_type: network.game_type(s.player.game_mode())
	})
	s.deliver(&packets_776.UpdateAbilitiesPacket{
		data: s.build_abilities_776()
	})
}
