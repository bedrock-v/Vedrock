# .codex

Codex-specific assets for the Vedrock project. The canonical project instructions live in the
repo-root `AGENTS.md`, which Codex reads automatically - this folder is for extras.

## prompts/

Custom slash prompts (the Codex equivalent of a Claude Code skill). Each `.md` file becomes a
`/name` command.

- `vedrock-plugin` - scaffold a new plugin, command, event listener, or entity type.
- `vedrock-verify` - type-check, test, and boot-smoke the build.

To use these globally instead of per-project, copy or symlink them into `~/.codex/prompts/`.

## What else can live here

Besides prompts, useful additions for a Codex-driven repo:

- `AGENTS.md` (repo root) - the primary instruction file. Already present.
- More prompts - e.g. a release/changelog prompt, a "add a default command" prompt, a protocol
  packet scaffold prompt. Add a markdown file per task.
- Project `config.toml` overrides live in global `~/.codex/config.toml`, not here.
