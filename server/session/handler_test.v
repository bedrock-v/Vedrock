module session

import server.internal.gamedata

struct RecordingHandler {
mut:
	called bool
}

fn (mut h RecordingHandler) handle_chat(mut ctx EventContext[string], sender &NetworkSession) {}

fn (mut h RecordingHandler) handle_attack(mut ctx EventContext[f32], attacker_name string, mut victim NetworkSession) {
	h.called = true
	ctx.val += 1.0
}

fn (mut h RecordingHandler) handle_death(mut victim NetworkSession, attacker_name string) {}

fn (mut h RecordingHandler) handle_gamemode_change(mut ctx EventContext[int], mut target NetworkSession) {}

fn (mut h RecordingHandler) handle_join(mut s NetworkSession) {}

fn (mut h RecordingHandler) handle_quit(mut s NetworkSession) {}

struct CancellingHandler {}

fn (mut h CancellingHandler) handle_chat(mut ctx EventContext[string], sender &NetworkSession) {}

fn (mut h CancellingHandler) handle_attack(mut ctx EventContext[f32], attacker_name string, mut victim NetworkSession) {
	ctx.cancel()
}

fn (mut h CancellingHandler) handle_death(mut victim NetworkSession, attacker_name string) {}

fn (mut h CancellingHandler) handle_gamemode_change(mut ctx EventContext[int], mut target NetworkSession) {}

fn (mut h CancellingHandler) handle_join(mut s NetworkSession) {}

fn (mut h CancellingHandler) handle_quit(mut s NetworkSession) {}

fn test_multi_handler_chain_cancels() {
	mut victim := &NetworkSession{}
	mut recorder := &RecordingHandler{}
	mut canceller := &CancellingHandler{}
	mut multi := new_multi_handler([Handler(recorder), Handler(canceller)])

	mut ctx := new_event_context[f32](5.0)
	multi.handle_attack(mut ctx, 'Attacker', mut victim)

	assert recorder.called
	assert ctx.val == 6.0
	assert ctx.is_cancelled()
}

fn test_multi_handler_via_hub() {
	mut hub := new_hub(gamedata.GameData{})
	mut recorder := &RecordingHandler{}
	hub.set_handler(new_multi_handler([Handler(recorder)]))

	mut victim := &NetworkSession{}
	mut ctx := new_event_context[f32](3.0)
	hub.handler.handle_attack(mut ctx, 'Attacker', mut victim)

	assert recorder.called
	assert ctx.val == 4.0
	assert !ctx.is_cancelled()
}
