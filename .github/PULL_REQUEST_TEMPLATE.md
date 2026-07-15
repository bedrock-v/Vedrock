<!-- Describe what this PR does and why. Keep it focused. -->

## Description


## Related issue
<!-- e.g. Fixes #1, Related to #2. Delete if none. -->


## Checklist
- [ ] `v -check .` is clean
- [ ] `v test server` is fully green
- [ ] Follows the conventions in AGENTS.md (OOP, `pub`/capitalized exports, no import cycles, minimal comments)
- [ ] Cross-session gameplay state is only mutated on the actor thread (via `hub.submit(...)`)
- [ ] No unrelated changes bundled in
