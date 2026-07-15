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

Build only with the pinned compiler - newer V master breaks this project.

- V compiler: `0.5.1` (commit `0c3183c`)
- vc bootstrap pin: `f461dfeb`

### Dependencies

Some modules aren't on VPM yet. Clone them into your V modules directory (`~/.vmodules` on
Linux/macOS, `%USERPROFILE%\.vmodules` on Windows):

```bash
git clone https://github.com/bedrock-v/nbt      ~/.vmodules/nbt
git clone https://github.com/bedrock-v/raknet   ~/.vmodules/raknet
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
v run .      # run without keeping a binary
v .          # debug build -> ./vedrock
```

## Running tests

```bash
v test server         # run every _test.v under server/
v test server/entity  # run one package's tests
```

A change is done only when `v -check .` is clean and `v test server` is fully green. This is the
same thing CI checks.

## Coding conventions

Full details are in [AGENTS.md](AGENTS.md). In short:

- OOP. Model with structs, interfaces, and methods, matching the surrounding code.
- Every exported struct/method is `pub` and the struct name is capitalized (V requirement).
- Keep new packages self-contained and avoid import cycles. Lower layers (`event`, `scheduler`,
  `entity`) must not import `session` - they take primitives or shared interfaces instead.
- Do not mutate cross-session gameplay state off the actor thread. Submit a `WorldJob` via
  `hub.submit(...)` instead. See the threading section in AGENTS.md.
- Comments: minimal, only where the "why" isn't obvious. Use "-" not em-dashes, and write them
  like a human would. Same for markdown docs.

## Commit style

Use a conventional-commit subject line (`feat:`, `fix:`, `docs:`, `refactor:` etc). A body is
optional - only add one when the subject doesn't explain the "why".

## Pull requests

- Keep changes focused and easy to review. No unrelated changes bundled in.
- Make sure `v -check .` and `v test server` pass before opening the PR.
- Fill in the pull request template and link any related issue.

By participating in this project, you are expected to follow the bedrock-v Code of Conduct.
