---
description: Scaffold new Vedrock content - plugins, commands, event listeners, entity types.
---

# Vedrock plugin scaffolding

Codex prompt. Use when adding a plugin, command, listener, or mob to Vedrock following the
existing codebase patterns. See `AGENTS.md` for build/test and the threading model.

Vedrock plugins are compiled in-tree (no disk loading). A plugin gets one `Api` handle
on enable and registers commands, listeners, and scheduled tasks through it. This prompt
covers the four common scaffolds. All templates compile against the current source.

Reference example: `server/plugin/sample/greeter.v`.

## Global gotchas

- Every exported struct and its methods must be `pub` and the struct name capitalized.
  V requires `pub struct`/`pub fn` for anything the plugin/server package touches.
- `ServerView` and `Sender` methods are `mut`. You cannot call them directly on an
  interface field or command value receiver. Copy the value to a `mut` local first:
  `mut s := c.server` then `s.spawn_entity(...)`.
- Commands are registered by value (the `Command` interface is a value), so `execute`
  takes `c Command` (value receiver). To mutate server state, hold a `ServerView` field
  and copy it to a `mut` local inside `execute`.
- Listeners embed `event.NopHandler` so you only define the events you care about.
- Scheduler ticks: 20 ticks = 1 second.

---

## 1. New plugin

Put it in its own package under `server/plugin/<name>/`. Embed `plugin.Base` for a
free scoped logger.

```v
module myplugin

import server.event
import server.plugin
import server.scheduler

pub struct MyPlugin {
	plugin.Base
mut:
	heartbeat &scheduler.TaskHandler = unsafe { nil }
}

pub fn (p &MyPlugin) meta() plugin.Meta {
	return plugin.Meta{
		name:    'MyPlugin'
		version: '1.0.0'
		authors: ['You']
	}
}

pub fn (mut p MyPlugin) on_enable(mut api plugin.Api) {
	api.register_command(MyCommand{})
	api.register_listener(&MyListener{}, event.Priority.normal)

	log := api.log
	p.heartbeat = api.run_repeating(scheduler.new_closure_task(fn [log] () {
		log.info('tick')
	}), 1200) // every 60s
}

pub fn (mut p MyPlugin) on_disable() {
	if p.heartbeat != unsafe { nil } {
		p.heartbeat.cancel()
	}
}
```

`Api` methods available:
- `register_command(c cmd.Command)`
- `register_listener(h event.Handler, priority event.Priority)`
- `run_delayed(task scheduler.Task, delay i64) &scheduler.TaskHandler`
- `run_repeating(task scheduler.Task, period i64) &scheduler.TaskHandler`
- `api.server` is a `ServerView`; `api.log` is a `&logger.Logger`.

`ServerView` methods (all `mut` - copy to a local): `broadcast_message(text)`,
`online_count() int`, `player_names() []string`,
`spawn_entity(name string, x f32, y f32, z f32) bool`, `entity_type_names() []string`.

**Register it.** Add one line to `register_plugins` in `server/server.v`:

```v
plugins.register(&myplugin.MyPlugin{})
```

and `import server.plugin.myplugin` at the top of `server/server.v`.

---

## 2. New command

Implement the `cmd.Command` interface. Value receivers throughout.

```v
struct MyCommand {}

pub fn (c MyCommand) name() string { return 'mycmd' }
pub fn (c MyCommand) description() string { return 'Does a thing' }
pub fn (c MyCommand) aliases() []string { return ['mc'] }
pub fn (c MyCommand) permission() string { return '' } // '' = public

pub fn (c MyCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{ arg_name: 'player' },
		cmd.IntArgument{ arg_name: 'count', arg_optional: true },
	]
}

pub fn (c MyCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	target := ctx.args[0]
	sender.send_message('§aHello ${target}')!
}
```

Argument types (`server/cmd/argument.v`), all take `arg_name` and optional `arg_optional`:
- `StringArgument` - one non-empty token
- `IntArgument` - one integer token
- `TargetArgument` - one connected-player name
- `TextArgument` - consumes the rest of the line (must be last)
- `StringEnumArgument` - fixed case-insensitive set; also takes `values []string`

Registry validates args before `execute` runs, so `ctx.args` is already the right shape;
optional args may be absent, so guard with `ctx.args.len`. `execute` returns `!` -
propagate `send_message(...)!`.

`ctx.args` are the raw string tokens. `ctx.lang` gives translations
(`ctx.lang.t('key')`, `ctx.lang.tf('key', {'Name': x})`).

`Sender` (value, methods are `mut`): `name()`, `is_player()`, `has_permission(name)`,
`send_message(msg) !`, `position() (f32,f32,f32)`, `find_player(name) ?Sender`,
`give_item(id, count) bool`, `teleport(x,y,z)`, `set_gamemode(mode)`, etc.
See `server/cmd/sender.v`.

**To mutate server state from a command**, hold a `ServerView` and copy to a mut local:

```v
struct SummonCommand {
mut:
	server plugin.ServerView
}

pub fn (c SummonCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	mut server := c.server // ServerView methods are mut - copy first
	x, y, z := sender.position()
	if !server.spawn_entity(ctx.args[0], x, y, z) {
		sender.send_message('§cunknown type')!
	}
}
```

Register with the field wired: `api.register_command(SummonCommand{ server: api.server })`.

Built-in commands live in `server/cmd/default/` (e.g. `give.v`) - same shape, but they
use `permission.command_*` nodes instead of `''`.

---

## 3. New event listener

Embed `event.NopHandler`, override only the events you need. Handler methods take a
`mut ctx event.Context[T]`. Mutate `ctx.val` to change the outcome; call `ctx.cancel()`
to cancel.

```v
struct MyListener {
	event.NopHandler
mut:
	server plugin.ServerView
}

pub fn (mut l MyListener) on_player_join(mut ctx event.Context[event.JoinData]) {
	ctx.val.message = '§a${ctx.val.player.name()} joined'
}

pub fn (mut l MyListener) on_block_break(mut ctx event.Context[event.BlockBreakData]) {
	if ctx.val.x == 0 && ctx.val.z == 0 {
		ctx.val.player.send_message('§cprotected') or {}
		ctx.cancel()
	}
}
```

Register: `api.register_listener(&MyListener{ server: api.server }, event.Priority.normal)`.
Priorities (`lowest low normal high highest monitor`): lowest runs first, monitor last -
`monitor` should only observe.

Events and their `ctx.val` fields (all in `server/event/events.v`; `player` is a
`cmd.Sender`):
- `on_player_join(JoinData)` - `player`, `message`
- `on_player_quit(QuitData)` - `player`, `message`
- `on_player_chat(ChatData)` - `player`, `message`
- `on_player_command(CommandData)` - `player`, `command`
- `on_block_break(BlockBreakData)` - `x y z block_id`, `player`
- `on_block_place(BlockPlaceData)` - `x y z block_id`, `player`
- `on_player_interact(InteractData)` - `x y z face`, `player`
- `on_player_attack(AttackData)` - `victim_runtime_id critical`, `player damage`
- `on_player_hurt(HurtData)` - `attacker_name`, `player amount`
- `on_player_death(DeathData)` - `params`, `player message_key`
- `on_player_respawn(RespawnData)` - `player x y z`
- `on_player_move(MoveData)` - `x y z`, `player` (editing coords is ignored; cancel snaps back)
- `on_gamemode_change(GameModeChangeData)` - `player mode`

`ctx.val.player.send_message(...)` returns `!` - swallow with `or {}` inside a handler
(handlers don't return an error).

---

## 4. New entity type

An entity type is a name mapped to a `BehaviourFactory` (`fn () Behaviour`). Each spawn
gets a fresh `Behaviour`. Reuse the shipped behaviours or write your own.

**Reuse a built-in behaviour** - register in `register_defaults` in
`server/entity/registry.v`:

```v
r.register('slime', fn () Behaviour {
	return &PassiveBehaviour{ network_id: 'minecraft:slime' }
})
```

`PassiveBehaviour` (idle, physics only) and `ProjectileBehaviour`
(flies, despawns on ground or after `max_age` ticks, default 100) are in
`server/entity/behaviour.v`.

**Custom behaviour** - implement the `Behaviour` interface:

```v
pub struct SpinBehaviour {
	network_id string
}

pub fn (b &SpinBehaviour) identifier() string { return b.network_id }

pub fn (mut b SpinBehaviour) tick(mut e Entity) {
	e.yaw += 10.0
	if e.age > 200 {
		e.kill()
	}
}
```

`identifier()` returns the network type id (e.g. `'minecraft:pig'`) sent to clients.
`tick(mut e Entity)` runs once per server tick before physics. Mutate the entity:
`e.set_velocity(v)`, `e.teleport(pos)`, `e.kill()`, or fields `e.yaw`, `e.pitch`,
`e.no_gravity`, `e.health`; read `e.age`, `e.on_ground`, `e.pos`. See
`server/entity/entity.v`.

Then register the factory:

```v
r.register('spinner', fn () Behaviour {
	return &SpinBehaviour{ network_id: 'minecraft:armor_stand' }
})
```

Names are lower-cased on register and lookup. Once registered, the type is spawnable via
`ServerView.spawn_entity(name, x, y, z)` and the `/summon` command.

---

## Quick checklist

- [ ] structs and methods are `pub` and capitalized
- [ ] listener embeds `event.NopHandler`
- [ ] `ServerView`/`Sender` calls go through a `mut` local
- [ ] plugin registered in `server/server.v` `register_plugins` (+ import)
- [ ] entity type registered in `server/entity/registry.v` `register_defaults`
- [ ] scheduled `TaskHandler` cancelled in `on_disable`
