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

// SetGamemodeJob is `set_gamemode` run through the actor.
struct SetGamemodeJob {
	runtime_id u64
	mode       int
}

fn (j SetGamemodeJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	target.apply_gamemode(j.mode)
}

fn (mut s NetworkSession) set_gamemode(mode int) {
	s.hub.submit(SetGamemodeJob{
		runtime_id: s.runtime_id
		mode:       mode
	})
}

// apply_gamemode is the actual mutation, run exclusively from run_jobs().
fn (mut s NetworkSession) apply_gamemode(mode int) {
	mut ctx := event.new_context(event.GameModeChangeData{
		player: s
		mode:   mode
	})
	s.hub.events.gamemode_change(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	s.game_mode = ctx.val.mode
	s.transport.send(&protocol.SetPlayerGameTypePacket{
		gamemode: s.game_mode
	}) or {}
	s.transport.send(&protocol.UpdateAbilitiesPacket{
		data: s.build_abilities()
	}) or {}
}
