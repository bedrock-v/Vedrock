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

## Commit style

Use a conventional-commit subject line (`feat:`, `fix:`, `docs:`, `refactor:` etc). A body is
optional - only add one when the subject doesn't explain the "why".

## Pull requests

- Keep changes focused and easy to review. No unrelated changes bundled in.
- Make sure `v -check .` and `v test server` pass before opening the PR.
- Fill in the pull request template and link any related issue.

By participating in this project, you are expected to follow the bedrock-v Code of Conduct.
