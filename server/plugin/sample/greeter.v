module sample

import server.cmd
import server.event
import server.internal.logger
import server.plugin
import server.scheduler

// GreeterPlugin is a worked example of the plugin API: it registers a command,
// an event listener and a repeating scheduled task on enable. Use it as a
// template for real plugins.
pub struct GreeterPlugin {
	plugin.Base
mut:
	heartbeat_task &scheduler.TaskHandler = unsafe { nil }
}

pub fn (p &GreeterPlugin) meta() plugin.Meta {
	return plugin.Meta{
		name:    'Greeter'
		version: '1.0.0'
		authors: ['Vedrock']
	}
}

pub fn (mut p GreeterPlugin) on_enable(mut api plugin.Api) {
	api.register_command(HelloCommand{})
	api.register_command(SummonCommand{
		server: api.server
	})
	api.register_listener(&GreeterListener{
		server: api.server
		log:    api.log
	}, event.Priority.normal)

	log := api.log
	server := api.server
	// One-shot 5s after boot.
	api.run_delayed(scheduler.new_closure_task(fn [log] () {
		log.info('Greeter warmed up')
	}), 100)
	// Every 60s: report how many players are online.
	p.heartbeat_task = api.run_repeating(scheduler.new_closure_task(fn [log, server] () {
		mut s := server
		log.info('${s.online_count()} player(s) online')
	}), 1200)
}

pub fn (mut p GreeterPlugin) on_disable() {
	if p.heartbeat_task != unsafe { nil } {
		p.heartbeat_task.cancel()
	}
}

// GreeterListener embeds NopHandler so it only has to define the events it uses.
struct GreeterListener {
	event.NopHandler
mut:
	server plugin.ServerView
	log    &logger.Logger = unsafe { nil }
}

// on_player_join replaces the default join line with a custom welcome.
pub fn (mut l GreeterListener) on_player_join(mut ctx event.Context[event.JoinData]) {
	ctx.val.message = '§a[+] §f${ctx.val.player.name()} §7joined - welcome!'
}

// on_player_chat blocks messages containing a banned word, showing the cancel
// path, and otherwise tags the message with the online count.
pub fn (mut l GreeterListener) on_player_chat(mut ctx event.Context[event.ChatData]) {
	if ctx.val.message.contains('badword') {
		ctx.val.player.send_message('§cThat word is not allowed here.') or {}
		ctx.cancel()
		return
	}
	ctx.val.message = '§7[${l.server.online_count()}]§r ${ctx.val.message}'
}

// on_block_break protects the spawn area (a 16x16 column around origin) from
// being mined - a typical minigame lobby guard.
pub fn (mut l GreeterListener) on_block_break(mut ctx event.Context[event.BlockBreakData]) {
	if ctx.val.x >= -8 && ctx.val.x <= 8 && ctx.val.z >= -8 && ctx.val.z <= 8 {
		ctx.val.player.send_message('§cYou cannot break blocks in spawn.') or {}
		ctx.cancel()
	}
}

pub fn (mut l GreeterListener) on_start_break(mut ctx event.Context[event.StartBreakData]) {
	if !isnil(l.log) {
		l.log.debug('${ctx.val.player.name()} started breaking block at (${ctx.val.x}, ${ctx.val.y}, ${ctx.val.z})')
	}
}

pub fn (mut l GreeterListener) on_player_interact(mut ctx event.Context[event.InteractData]) {
	if !isnil(l.log) {
		l.log.debug('${ctx.val.player.name()} interacted with block at (${ctx.val.x}, ${ctx.val.y}, ${ctx.val.z}) face=${ctx.val.face}')
	}
}

// on_item_use fires right before a held item's effect applies.
pub fn (mut l GreeterListener) on_item_use(mut ctx event.Context[event.ItemUseData]) {
	if isnil(l.log) {
		return
	}
	if ctx.val.on_block {
		l.log.debug('${ctx.val.player.name()} used ${ctx.val.item_name} on block at (${ctx.val.x}, ${ctx.val.y}, ${ctx.val.z})')
	} else {
		l.log.debug('${ctx.val.player.name()} used ${ctx.val.item_name} in the air')
	}
}

// on_player_death rewrites the death broadcast with a custom format.
pub fn (mut l GreeterListener) on_player_death(mut ctx event.Context[event.DeathData]) {
	l.server.broadcast_message('§7[§c☠§7] §f${ctx.val.player.name()} §7died.')
	ctx.cancel() // suppress the default vanilla death message
}

// HelloCommand is a trivial command registered by the plugin.
struct HelloCommand {}

pub fn (c HelloCommand) name() string {
	return 'hello'
}

pub fn (c HelloCommand) description() string {
	return 'Greet the sender - added by the Greeter plugin'
}

pub fn (c HelloCommand) aliases() []string {
	return ['hi']
}

pub fn (c HelloCommand) permission() string {
	return ''
}

pub fn (c HelloCommand) arguments() []cmd.Argument {
	return []
}

pub fn (c HelloCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	sender.send_message('§bHello, ${sender.name()}! §7(from the Greeter plugin)')!
}

// SummonCommand spawns an entity by type name at the sender's position, using
// the entity system through the plugin ServerView.
struct SummonCommand {
mut:
	server plugin.ServerView
}

pub fn (c SummonCommand) name() string {
	return 'summon'
}

pub fn (c SummonCommand) description() string {
	return 'Spawn an entity at your position - added by the Greeter plugin'
}

pub fn (c SummonCommand) aliases() []string {
	return []
}

pub fn (c SummonCommand) permission() string {
	return ''
}

pub fn (c SummonCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name: 'type'
		},
	]
}

pub fn (c SummonCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if !sender.is_player() {
		sender.send_message('§cOnly players can summon entities.')!
		return
	}
	// ServerView's methods are mut; copy the interface value to a mut local so
	// the call lands on the underlying server.
	mut server := c.server
	kind := ctx.args[0]
	x, y, z := sender.position()
	if server.spawn_entity(kind, x, y, z) {
		sender.send_message('§aSummoned §f${kind}§a.')!
	} else {
		sender.send_message('§cUnknown entity type "${kind}". Available: ${server.entity_type_names().join(', ')}')!
	}
}
