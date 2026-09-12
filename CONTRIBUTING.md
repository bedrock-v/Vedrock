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

### V compiler

Vedrock is built with **V 3**, the current V compiler. V 1, reached through `-old-compiler`, is
legacy: it stays in V for a while yet and then goes and nothing here is written for it. Don't add
`-old-compiler` to a command and don't shape code around a V 1 limitation.

CI pins a commit so a build is reproducible and the pin is bumped as V moves:

- V compiler: `0.5.2` (commit `3058788`)
- vc bootstrap pin: `e658629`

The pin is a version, not a ceiling: a newer V master is expected to work and a break against one
is a bug to report upstream rather than a reason to go back to V 1.

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

### A generic method that stores an interface typed `T` may be emitted for only one interface

This is the one confirmed compiler bug in this list and it still reproduces on the current pin.

`server/scheduler` and `server/worldrt/world_scheduler.v` used to be two separate near identical
implementations because of it. They now share `scheduler.Table[T]`/`scheduler.Handler[T]`, under a
narrow constraint that the sharing has to keep.

The bug: a generic struct that stores an interface typed generic field (`struct Handler[T] { task T }`
where `T` is itself an interface) miscompiles when a method that *performs that store* is emitted for
two different interface types. The second instantiation's body gets an `as_cast` to the first one's
interface:

```c
_t1->task = I_tbl__Task_as_I_wrld__WorldTask(task);
```

inside `Table[Task]`'s own `add()` - the body compiled for the `Task` instantiation casting through
`WorldTask`.

What this permits and forbids:

- Every method that does *not* store a `T` is fine emitted for both interfaces. `due`, `settle`,
  `cancel`, `cancel_all`, `count`, `work`, `id`, `is_cancelled` and `is_repeating` all are.
- The methods that *do* store a `T` - `add` and `add_now` - may each be emitted for only one. `add`
  is the world side's, `add_now` the global side's. That is why `add_now` repeats `add`'s body
  instead of calling it: calling it would pull `add` into both instantiations and bring the bug back.

So don't add a caller that schedules through the other one's entry point and don't refactor the two
bodies back together. Both mistakes break the C compile rather than corrupting data, so they're loud
but the error points at generated C and is hard to read back to this rule.

`server/session/scheduler_instantiation_test.v` is what proves the sharing sound: it is the only
place that links both modules and schedules on both, so both instantiations land in one binary.

This is the same general family as the existing `world_call[T]`/`CallJob` rule (genericity lives only
on a free function, never on a struct dispatched through an interface) - this finding extends it to
cover a generic struct merely *storing* an interface typed field, not just being dispatched through
one itself.

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

## Coding style

See [`docs/coding_style.md`](docs/coding_style.md) - naming, formatting, comments and how
this project uses V's error handling/interfaces/sum types instead of patterns carried over
from other languages. Run `v fmt -w` on touched files.

## Commit style

Use a conventional-commit subject line (`feat:`, `fix:`, `docs:`, `refactor:` etc). A body is
optional - only add one when the subject doesn't explain the "why".

## Pull requests

- Keep changes focused and easy to review. No unrelated changes bundled in.
- Make sure `v -check .` and `v test server` pass before opening the PR.
- Fill in the pull request template and link any related issue.

By participating in this project, you are expected to follow the bedrock-v Code of Conduct.
