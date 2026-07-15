module event

// TagHandler embeds NopHandler and only records that it ran, appending its tag
// to the join message so ordering is observable.
struct TagHandler {
	NopHandler
	tag string
}

fn (mut h TagHandler) on_player_join(mut ctx Context[JoinData]) {
	ctx.val.message += h.tag
}

// CancelHandler cancels every chat it sees.
struct CancelHandler {
	NopHandler
}

fn (mut h CancelHandler) on_player_chat(mut ctx Context[ChatData]) {
	ctx.cancel()
}

fn test_dispatch_runs_in_priority_order() {
	mut bus := new_bus()
	// Register out of order; lowest must still run first.
	bus.register(&TagHandler{ tag: 'C' }, .high)
	bus.register(&TagHandler{ tag: 'A' }, .lowest)
	bus.register(&TagHandler{ tag: 'B' }, .normal)

	mut ctx := new_context(JoinData{ message: '' })
	bus.player_join(mut ctx)
	assert ctx.val.message == 'ABC'
	assert bus.len() == 3
}

fn test_handler_can_mutate_value() {
	mut bus := new_bus()
	bus.register(&TagHandler{ tag: '!' }, .normal)

	mut ctx := new_context(JoinData{ message: 'hi' })
	bus.player_join(mut ctx)
	assert ctx.val.message == 'hi!'
}

fn test_handler_can_cancel() {
	mut bus := new_bus()
	bus.register(&CancelHandler{}, .normal)

	mut ctx := new_context(ChatData{ message: 'spam' })
	assert !ctx.is_cancelled()
	bus.player_chat(mut ctx)
	assert ctx.is_cancelled()
}

// DamageHalver halves attack damage, exercising a mutable non-cancel field.
struct DamageHalver {
	NopHandler
}

fn (mut h DamageHalver) on_player_attack(mut ctx Context[AttackData]) {
	ctx.val.damage /= 2
}

fn test_attack_damage_is_mutable() {
	mut bus := new_bus()
	bus.register(&DamageHalver{}, .normal)
	mut ctx := new_context(AttackData{ damage: 10.0 })
	bus.player_attack(mut ctx)
	assert ctx.val.damage == 5.0
	assert !ctx.is_cancelled()
}

// SpawnGuard cancels every block break, like a lobby protector.
struct SpawnGuard {
	NopHandler
}

fn (mut h SpawnGuard) on_block_break(mut ctx Context[BlockBreakData]) {
	ctx.cancel()
}

fn test_block_break_can_be_cancelled() {
	mut bus := new_bus()
	bus.register(&SpawnGuard{}, .normal)
	mut ctx := new_context(BlockBreakData{ x: 1, y: 2, z: 3, block_id: 7 })
	bus.block_break(mut ctx)
	assert ctx.is_cancelled()
}

fn test_empty_bus_is_noop() {
	mut bus := new_bus()
	mut ctx := new_context(JoinData{ message: 'unchanged' })
	bus.player_join(mut ctx)
	assert ctx.val.message == 'unchanged'
	assert !ctx.is_cancelled()
}
