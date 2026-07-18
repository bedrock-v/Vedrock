# AGENTS.md

Guidance for AI coding agents (and humans) working on Vedrock - a Minecraft: Bedrock Edition
server written in V. This is the canonical instruction file; `CLAUDE.md` points here.

## What this is

Vedrock is an early-stage Bedrock server. It accepts RakNet connections, speaks the Bedrock
protocol, and runs a tick-based game loop. Core gameplay (blocks, combat, worlds, inventory,
forms, permissions) plus an in-tree plugin system, event bus, scheduler, entity system, world
management API, and a chunk upgrader.

## Build, test, run

Build ONLY with the pinned compiler - newer V master breaks the build:

- V compiler: `0.5.2` (commit `f1ef640`)
- vc bootstrap pin: `bd654de`

Commands:

```sh
v -check .        # type-check the whole project - fast, use this while iterating
v .               # full debug build -> ./vedrock
v -prod -o main . # release build
v test server     # run every _test.v under server/
v test server/entity   # run one package's tests
```

A change is done only when `v -check .` is clean and `v test server` is fully green.

### Dependencies

Some modules are not on VPM yet. Clone them into `~/.vmodules` (see README):
`nbt`, `raknet`, `protocol` (from github.com/bedrock-v), `i18n` (from github.com/nepinhum).
`server/world/db` also needs a local leveldb. The dependency modules are git-cloned and
symlinked into `~/.vmodules`; symlinks must point outside `VMODULES`.

## Architecture

Entry: `main.v` -> `server.new(cfg)` -> `srv.start()`.

- `server/` - the server package tree, one subpackage per concern.
- `server/session/` - `NetworkSession` (one per connection) and `Hub` (shared server state).
- `server/session/hub.v` - `Hub` owns worlds, commands, events, scheduler, entities, sessions.

### Threading model - read before touching shared state

- Each connection runs on its own thread (`NetworkSession.handle_loop`).
- `Hub.run_jobs()` is a single actor thread draining a `WorldJob` channel. It is the ONLY
  place allowed to mutate gameplay state that spans sessions (combat, gamemode, world swaps).
- To mutate cross-session state off the connection thread, submit a `WorldJob` via
  `hub.submit(...)` - do not mutate directly.
- `server/server.v` `tick_loop` submits one `TickJob` per tick (20 TPS). `TickJob.run` (on the
  actor thread) advances world time, the scheduler heartbeat, and the entity tick.
- Subsystems added later (scheduler, entity manager) are mutex-guarded so they are safe to
  touch from any thread, but their tick runs on the actor thread.

### Subsystems

- `server/plugin/` - in-tree plugin system. A `Plugin` gets one `Api` on enable to register
  commands, event listeners, and scheduled tasks. Built-ins wired in `server/server.v`
  `register_plugins`. Example: `server/plugin/sample/greeter.v`.
- `server/event/` - Event bus. Generic `Context[T]` (`context.v`) and the
  narrow `PlayerView` interface (`player.v`), a `Handler` interface with one method per event,
  embeddable `NopHandler`, priority-ordered `Bus`. 15 events dispatched from real session hooks
  (join/quit/chat/command/block break-place/start-break/interact/item-use/attack/hurt/death/
  respawn/move/gamemode). Event data structs are grouped by domain: `events_player.v`,
  `events_block.v`, `events_item.v`, `events_combat.v`.
- `server/scheduler/` - PocketMine-style tick scheduler. `Task`/`ClosureTask`, `TaskHandler`,
  delayed + repeating, mutex-guarded, `heartbeat(tick)` on the actor thread. 20 ticks = 1s.
- `server/entity/` - non-player actors (mobs/projectiles). `Entity` + pluggable `Behaviour`
  (dragonfly model), a `Registry` (name -> factory), a mutex-guarded `Manager`. Players stay
  as `NetworkSession`. Spawn via `ServerView.spawn_entity` or `/summon`.
- `server/world/db/` - LevelDB-backed worlds. Management API in `manage.v` + `Hub` methods
  (`create_world`/`unload_world`/`delete_world`/`list_worlds`/`world_info`), exposed via the
  `/world` command. Deletion refuses the default world and worlds with players, always closes
  the LevelDB handle before removing files, and blocks path traversal.
- `server/world/upgrader/` - schema-driven block-state upgrader (df-mc/worldupgrader model).
  Versioned upgrade steps (rename, meta->state, value remap) applied on chunk load via a hook
  in `server/world/db/vanilla.v`; current-version data is a pass-through no-op.
- `server/cmd/` - `Command` interface + `Registry`. Defaults in `server/cmd/default/`.
- `server/permission/`, `server/form/`, `server/resource/`, `server/item/`, `server/block/`.

## Conventions

- OOP. Model with structs, interfaces, and methods - match the surrounding code's idioms.
- Comments: minimal. Only where the "why" isn't obvious. Use "-" not em-dashes, and write them
  like a human would. Do not narrate the obvious.
- Documentation/markdown: use "-" not em-dashes.
- Keep new packages self-contained and avoid import cycles - lower layers (`event`, `scheduler`,
  `entity`) must not import `session`. They take primitives or their own narrow interfaces
  instead - each layer declares exactly what it needs and lets `NetworkSession`/`Hub` satisfy it
  structurally (see `event.PlayerView`, `plugin.ServerView`, `world/light`'s engine interface).
- Every exported struct/method is `pub` and the struct name is capitalized (V requirement).

## Extending the server

There is a scaffolding guide for the four most common additions (plugin, command, listener,
entity type) with copy-pasteable templates:

- Claude Code: skill at `.claude/skills/vedrock-plugin/SKILL.md` (invoke `/vedrock-plugin`).
- Codex / other tools: prompt at `.codex/prompts/vedrock-plugin.md`.

Register points: plugins in `server/server.v` `register_plugins`; entity types in
`server/entity/registry.v` `register_defaults`; default commands in
`server/cmd/default/register.v`.

## Do not

- Do not build with a V version other than the pin.
- Do not mutate cross-session gameplay state off the actor thread.
- Do not commit unless asked.
