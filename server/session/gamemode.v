module session

import server.event
import server.player
import bedrock_v.protocol.current as proto

fn gamemode_from_wire(v int) player.Gamemode {
	return match v {
		proto.game_type_creative {
			.creative
		}
		proto.game_type_adventure {
			.adventure
		}
		proto.game_type_spectator, proto.game_type_survival_spectator,
		proto.game_type_creative_spectator {
			.spectator
		}
		else {
			.survival
		}
	}
}

fn gamemode_to_wire(g player.Gamemode) int {
	return match g {
		.survival { proto.game_type_survival }
		.creative { proto.game_type_creative }
		.adventure { proto.game_type_adventure }
		.spectator { proto.game_type_spectator }
	}
}

fn gamemode_from_name(name string) player.Gamemode {
	return match name.to_lower() {
		'survival' { .survival }
		'adventure' { .adventure }
		'spectator' { .spectator }
		else { .creative }
	}
}

// PlayerSetGamemodeTask is set_gamemode() run through the owning world's
// actor. epoch is checked via player_for_epoch so a stale request (e.g. an
// /gamemode command submitted just before a world switch) produces zero
// side effects.
struct PlayerSetGamemodeTask {
	runtime_id u64
	epoch      i64
	mode       player.Gamemode
}

fn (t PlayerSetGamemodeTask) name() string {
	return 'PlayerSetGamemodeTask'
}

fn (t PlayerSetGamemodeTask) run(mut tx WorldTx) {
	mut s := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	s.apply_gamemode(mut tx.wr.events, t.mode)
}

fn (mut s NetworkSession) set_gamemode(mode player.Gamemode) {
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
fn (mut s NetworkSession) apply_gamemode(mut events event.Bus, mode player.Gamemode) {
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
		player_game_type: proto.game_type(gamemode_to_wire(s.player.game_mode()))
	})
	s.deliver(&proto.UpdateAbilitiesPacket{
		data: s.build_abilities()
	})
}
