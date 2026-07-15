# CLAUDE.md

Project guidance for Claude Code. The canonical, tool-agnostic instructions live in
`AGENTS.md` - read it first:

@AGENTS.md

## Claude-specific

- Scaffolding skill: `/vedrock-plugin` (`.claude/skills/vedrock-plugin/SKILL.md`) generates
  new plugins, commands, event listeners, and entity types from the current APIs.
- Quick verify loop: `v -check .` then `v test server`. Both must pass before declaring done.
- Build only with V 0.5.1 (0c3183c) - see AGENTS.md for the full pin and dependency layout.
