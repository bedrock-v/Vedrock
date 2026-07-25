# CLAUDE.md

Project guidance for Claude Code. The canonical, tool-agnostic instructions live in
`AGENTS.md` - read it first:

@AGENTS.md

## Claude-specific

- Quick verify loop: `v -check .` then `v test server`. Both must pass before declaring done.
- Build only with V 0.5.2 (f1ef640) - see AGENTS.md for the full pin and dependency layout.
