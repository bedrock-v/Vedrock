# Vedrock coding style

This document exists because "looks like the file next to it" is not a style guide.

## 0. Philosophy

Code is written for the compiler first, the next contributor second and nobody's personal
taste third.

V already removes most style arguments before they start: there is one formatter (`v fmt`),
one way to handle an absent value (no null), one way to handle a recoverable error (`or {}` /
`?` / `!`, no exceptions) and one way to extend behavior without inheritance (interfaces and
sum types). Where V gives you exactly one way to do something, use that way and do not
route around it to make the code read more like a language it isn't.

"Readable" doesn't mean "reads like English." A function that hides a fallible operation
behind something that looks like it can't fail is less readable than one that makes the
`or {}` visible, even though the second one has more punctuation. Optimize for the shape of
the problem V is solving underneath, not for how the line sounds read aloud. When something
genuinely needs a plain language explanation for the next person, that's what a comment is
for. See [Comments](#5-comments). The goal isn't to make code obscure, it's to stop dressing
computer logic up as something it isn't.

## 1. Formatting

Run `v fmt -w` on every file you touch before it's done.

`v fmt` writes real tab characters for indentation. Your editor's "insert spaces" / "hard tabs"
setting only controls what happens while *you* are typing; `v fmt` normalizes the file
afterward regardless of what your editor did. Set your editor to display tabs at whatever
width you personally find readable. It changes nothing about the file on disk, only how wide a tab renders on your
screen. Don't hand align things with spaces to fight what `v fmt` will do to them anyway.

If `v fmt`'s output looks wrong for a specific construct, that's a question for upstream V,
not a reason to hand format around it locally.

## 2. Naming

Follow vlib's own convention (see e.g. `os`, `strings` in the V standard library) rather than
habits carried over from another language:

- functions, methods, variables, parameters, module names: `snake_case`
- struct / enum / interface / sum type names: `PascalCase`
- constants: `snake_case`, **not** `SCREAMING_SNAKE_CASE` - `pub const max_path_len = 4096`,
  not `MAX_PATH_LEN`.
- a name should say what the value *is* or what the function *does*, not how it's implemented
  (`entities`, not `entity_hashmap`; `broadcast_near`, not `broadcast_near_using_distance_sq`)

## 3. Reach for V's actual tools before reinventing them

- No null: don't simulate "no value" with a sentinel (`-1`, empty string, zero id) when an
  `Option` (`?T`) or a `or {}` result already says it directly. A sentinel is a fact only the
  author remembers; the type system doesn't know about it and won't stop it from leaking.
- No exceptions: propagate failure with `!`/`?` and handle it with `or {}` at the point that
  actually knows what to do about it. Don't `panic()` or `exit()` out of a recoverable
  condition in library shaped code (`server/*`); reserve those for invariants that are
  genuinely programmer errors, not for input or runtime conditions a caller could hit.
- No inheritance: reach for an interface (dispatch) or a sum type (closed set of shapes)
  instead of a struct trying to act as a base class via embedding. Vedrock's
  `entity.Actor` / `entity.Behaviour` split is the existing example to match, not a special
  case to work around.
- Generics stay on free functions in this codebase, not on structs that store an interface
  field. See `CONTRIBUTING.md`'s compiler behavior notes before changing that.

## 4. Function size

Functions should be short and do one thing. As a rule of thumb, a function that doesn't fit
on one or two screens or that needs more than 5-6 locally scoped variables to track its own
state has usually stopped doing one thing. Pull the sub steps into helper functions with
names that say what they do. V will inline trivial ones for you if it's actually
performance sensitive and it'll generally do a better job of deciding that than you would by
hand.

The limit bends with the shape of the logic, not just its line count: a long but flat `match`
that handles one case per packet type or block id is fine at a length a deeply nested
handler wouldn't be. If a function needs a table of contents to read, split it; if it's one
concept executed linearly, length alone isn't the problem.

## 5. Comments

- `//` only. Never `/* */`, anywhere, including if you find one already in the codebase,
  replace it while you're in that file.
- Comments say **what** and **why**, generally not **how**. If the how isn't obvious from the code
  itself, that's a signal to rewrite the code, not to explain it. An exception worth taking:
  a short note flagging something intentionally clever, unusual or ugly (a V/compiler
  workaround, a non obvious ordering requirement). Those earn a comment precisely because
  the reader can't be expected to reconstruct the reasoning from the code alone.
- Prefer commenting at the top of a function over scattering comments through its body. If a
  function needs its internals separately narrated piece by piece, that's usually a function
  size problem (see above) before it's a comments problem.
- Doc comments on `pub fn` follow vlib's convention: start with the function's own name,
  third person, describing what it returns or does.
  `// find_between_pair_u8 returns the substring between the first start and matching end`.
  This isn't decorative; `vdoc` and IDE hovers surface exactly this line.
- Don't leave a comment describing a previous version of the code. Git history already carries that; a stale migration note left
  in the source is actively misleading to the next reader who has no reason to doubt it.

## 6. Elsewhere in this repo

- `CONTRIBUTING.md` - build/test commands, the V compiler pin and the specific V codegen
  behaviors this codebase has had to design around. Read it before touching anything
  compiler sensitive.

This document covers how code is *written*. It intentionally says nothing about what gets
built or in what order, that's tracked separately: not in a style guide.

## Last edited - 2026-08-30, UTC 13:15 - by schermann.
