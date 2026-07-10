module session

import protocol

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
	mut ctx := new_event_context[int](j.mode)
	h.handler.handle_gamemode_change(mut ctx, mut target)
	if ctx.is_cancelled() {
		return
	}
	target.apply_gamemode(ctx.val)
}

fn (mut s NetworkSession) set_gamemode(mode int) {
	s.hub.submit(SetGamemodeJob{
		runtime_id: s.runtime_id
		mode:       mode
	})
}

// apply_gamemode is the actual mutation, run exclusively from run_jobs().
fn (mut s NetworkSession) apply_gamemode(mode int) {
	s.game_mode = mode
	s.transport.send(&protocol.SetPlayerGameTypePacket{
		gamemode: mode
	}) or {}
	s.transport.send(&protocol.UpdateAbilitiesPacket{
		data: s.build_abilities()
	}) or {}
}
