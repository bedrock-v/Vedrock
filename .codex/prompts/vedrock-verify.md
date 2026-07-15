---
description: Verify the Vedrock build - type-check, run tests, and boot-smoke the server.
---

# Verify Vedrock

Run the full verification loop and report results concisely. Stop at the first hard failure and
show the error.

1. Type-check the whole project:

   ```sh
   v -check .
   ```

2. Run the test suite:

   ```sh
   v test server
   ```

3. Build and boot-smoke (confirm it starts, then kill after ~3s):

   ```sh
   v -o /tmp/vedrock_smoke .
   /tmp/vedrock_smoke & PID=$!; sleep 3; kill $PID 2>/dev/null
   ```

Report: check result, test pass/total, and whether it logged "Started successfully". A change
is done only when steps 1 and 2 are fully green.

Build only with V 0.5.1 (0c3183c). See `AGENTS.md` for the pin and dependency layout.
