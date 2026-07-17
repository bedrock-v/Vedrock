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

struct UseLogger {
	NopHandler
mut:
	last_item     string
	last_on_block bool
}

fn (mut h UseLogger) on_item_use(mut ctx Context[ItemUseData]) {
	h.last_item = ctx.val.item_name
	h.last_on_block = ctx.val.on_block
}

// UseBlocker cancels every item use, like a minigame lobby disabling bone
// meal/goat horns.
struct UseBlocker {
	NopHandler
}

fn (mut h UseBlocker) on_item_use(mut ctx Context[ItemUseData]) {
	ctx.cancel()
}

fn test_item_use_can_be_cancelled() {
	mut bus := new_bus()
	bus.register(&UseBlocker{}, .normal)
	mut ctx := new_context(ItemUseData{ item_name: 'minecraft:bone_meal', on_block: true })
	assert !ctx.is_cancelled()
	bus.item_use(mut ctx)
	assert ctx.is_cancelled()
}

fn test_item_use_dispatch_reports_air_and_block_uses() {
	mut bus := new_bus()
	mut logger := &UseLogger{}
	bus.register(logger, .normal)

	mut air_ctx := new_context(ItemUseData{ item_name: 'minecraft:goat_horn' })
	bus.item_use(mut air_ctx)
	assert logger.last_item == 'minecraft:goat_horn'
	assert !logger.last_on_block

	mut block_ctx := new_context(ItemUseData{
		item_name: 'minecraft:bone_meal'
		on_block:  true
		x:         1
		y:         2
		z:         3
	})
	bus.item_use(mut block_ctx)
	assert logger.last_item == 'minecraft:bone_meal'
	assert logger.last_on_block
}

// StartBreakGuard cancels every start break, mirroring SpawnGuard's
// block break protection but for the earlier left click moment.
struct StartBreakGuard {
	NopHandler
}

fn (mut h StartBreakGuard) on_start_break(mut ctx Context[StartBreakData]) {
	ctx.cancel()
}

fn test_start_break_is_cancellable() {
	mut bus := new_bus()
	bus.register(&StartBreakGuard{}, .normal)
	mut ctx := new_context(StartBreakData{ x: 1, y: 2, z: 3, face: 1 })
	assert !ctx.is_cancelled()
	bus.start_break(mut ctx)
	assert ctx.is_cancelled()
}

fn test_empty_bus_is_noop() {
	mut bus := new_bus()
	mut ctx := new_context(JoinData{ message: 'unchanged' })
	bus.player_join(mut ctx)
	assert ctx.val.message == 'unchanged'
	assert !ctx.is_cancelled()
}
