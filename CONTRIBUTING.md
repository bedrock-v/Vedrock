# Contributing to Vedrock

Thanks for your interest in Vedrock - a Minecraft: Bedrock Edition server written in [V](https://vlang.io/).

Vedrock is early-stage (alpha), so APIs, project structure and behaviour still change often.
Contributions are welcome: bug reports, feature proposals, docs, and pull requests.

## Reporting bugs and proposing features

Use the issue templates. For questions and general discussion, use
[Discussions](https://github.com/bedrock-v/Vedrock/discussions), not the issue tracker.

For anything larger than a small fix, opening an issue first is recommended so the design can be
discussed before you write code.

## Building from source

### V compiler pin

Build only with the pinned compiler - newer V master **may** break this project.

- V compiler: `0.5.2` (commit `f1ef640`)
- vc bootstrap pin: `f461dfeb`

### Dependencies

Some modules aren't on VPM yet. Clone them into your V modules directory (`~/.vmodules` on
Linux/macOS, `%USERPROFILE%\.vmodules` on Windows):

```bash
git clone https://github.com/bedrock-v/nbt      ~/.vmodules/nbt
git clone https://github.com/bedrock-v/nethernet ~/.vmodules/nethernet
git clone https://github.com/bedrock-v/webrtc-v  ~/.vmodules/webrtc
git clone https://github.com/bedrock-v/protocol ~/.vmodules/protocol

v install nepinhum.i18n
```

`server/world/db` also needs a local leveldb module:

```bash
git clone --depth 1 https://github.com/vlang/leveldb ~/.vmodules/leveldb
```

### Build and run

```bash
git clone https://github.com/bedrock-v/Vedrock.git
cd Vedrock

v -check .   # type-check the whole project - fast, use while iterating
v run .      # run without keeping a binary (main.v is not something you should use on your production server)
v .          # debug build -> ./vedrock
```

## Running tests

```bash
v test server         # run every _test.v under server/
v test server/entity  # run one package's tests
```

A change is done only when `v -check .` is clean and `v test server` is fully green. This is the
same thing CI checks.

## Observed V compiler and language behaviors

These are V-specific behaviors observed and reproduced while developing Vedrock. Some may be
compiler bugs; others may be intentional language semantics or implementation details that aren't
clearly documented upstream. They're recorded here as project constraints to work around, not as
claims about V's intended behavior and they've already cost real debugging time in this codebase.
If a "cleanup" PR reintroduces one of these shapes, expect it to either fail to compile in a
confusing way or misbehave at runtime in a way that's hard to trace back to the cause.

### Don't unify the global/world schedulers with a generic `Scheduler[T]`

This is the one confirmed compiler bug in this list.

`server/scheduler` (global) and `server/session/world_scheduler.v` (per-world) share near identical
due task bookkeeping (id/delay/period/next_run/cancelled) but are kept as two separate, non generic
types on purpose - this was a deliberate choice, not an oversight.

Confirmed by direct reproduction: a generic struct that stores an interface typed
generic field (e.g. `struct Handler[T] { task T }` where `T` is itself an interface), instantiated
for more than one concrete interface type in the same program with at least one instantiation's
method reached through a `spawn` closure, causes V to crosswire the monomorphized method bodies in
the generated C. In the reproduction this didn't even compile:

```
error: incompatible types when assigning to type 'main__TaskA' from type 'main__TaskB'
```

from a generated line inside `GenScheduler[TaskA]`'s own `add()` method:

```c
_t1->task = I_main__TaskA_as_I_main__TaskB(task);
```

i.e. the method body compiled for the `TaskA` instantiation was casting through `TaskB` - the two
instantiations' generated code got crosswired. A less lucky version of this shape could compile
and corrupt data silently instead of failing to build.

This is the same general family as the existing `world_call[T]`/`CallJob` rule (genericity lives
only on a free function, never on a struct dispatched through an interface) - this finding extends
it to cover a generic struct merely *storing* an interface typed field, not just being dispatched
through one itself.

Keep the two scheduler implementations separate until upstream V fixes this class of bug. If
you're tempted to unify them again, reproduce the bug fresh against the current V version first.
Don't assume it still applies without checking, and don't merge them "to be safe" without checking
either.

### Closures copy a `mut` struct receiver by value

Copying avoids a closure silently outliving and aliasing a receiver V has no borrow checker to reason about but it's easy to get bitten by if you don't know it's happening. A closure literal like `fn [s] (...) {...}`, where `s`
is a `mut s SomeStruct` method receiver, copies the *entire struct* into the closure's own
environment at the moment the closure is built even when the struct is `@[heap]` and every
ordinary method call on it behaves referentially. Pointer/interface/channel/map/slice *fields*
still alias correctly through that copy; only the struct's own plain value fields (bools, ints,
small value structs) go silently stale.

What to do instead: take a real pointer via `unsafe { &s }` *before* the closure literal is built
and capture that instead of `s`. See `NetworkSession.self_ref()` (`server/session/session.v`) for
the established pattern and `self_ref_test.v` for the lifetime regression test that goes with it.

### Narrowing a shared interface (e.g. `entity.Actor`) to a concrete type

V wants an exact type match when narrowing an
interface value, with no implicit pointer/value coercion doing anything "magic" behind your back.
Use the bare type name (`if a is NetworkSession`), not a pointer form when narrowing - see
`entity/actor.v`'s own doc comment on `Actor` for the standing rule.

### Narrowed-interface-plus-method-call hazard - retested 2026-08-29, retired

Everything that *could* be tested, nothing reproduced it.

## Commit style

Use a conventional-commit subject line (`feat:`, `fix:`, `docs:`, `refactor:` etc). A body is
optional - only add one when the subject doesn't explain the "why".

## Pull requests

- Keep changes focused and easy to review. No unrelated changes bundled in.
- Make sure `v -check .` and `v test server` pass before opening the PR.
- Fill in the pull request template and link any related issue.

By participating in this project, you are expected to follow the bedrock-v Code of Conduct.
