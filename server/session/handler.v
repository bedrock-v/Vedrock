module session

// Handler receives world/player events from inside run_jobs(), so
// implementations may mutate NetworkSession/Hub state directly without
// locking anything. Each method's EventContext.cancel() lets the handler
// veto the action before its caller applies it.
pub interface Handler {
mut:
	handle_chat(mut ctx EventContext[string], sender &NetworkSession)
	handle_attack(mut ctx EventContext[f32], attacker_name string, mut victim NetworkSession)
	handle_death(mut victim NetworkSession, attacker_name string)
	handle_gamemode_change(mut ctx EventContext[int], mut target NetworkSession)
	handle_join(mut s NetworkSession)
	handle_quit(mut s NetworkSession)
}

// NopHandler is Hub's default Handler: every event passes through unmodified.
pub struct NopHandler {}

fn (mut h NopHandler) handle_chat(mut ctx EventContext[string], sender &NetworkSession) {}

fn (mut h NopHandler) handle_attack(mut ctx EventContext[f32], attacker_name string, mut victim NetworkSession) {}

fn (mut h NopHandler) handle_death(mut victim NetworkSession, attacker_name string) {}

fn (mut h NopHandler) handle_gamemode_change(mut ctx EventContext[int], mut target NetworkSession) {}

fn (mut h NopHandler) handle_join(mut s NetworkSession) {}

fn (mut h NopHandler) handle_quit(mut s NetworkSession) {}
