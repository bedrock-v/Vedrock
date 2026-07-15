---
description: Format the Vedrock source tree with v fmt and report what changed.
---

# Format Vedrock

Format the whole project in place and summarize:

```sh
v fmt -w .
```

Then show which files changed:

```sh
git status --short
```

Report the list of reformatted files. Do not commit. If `v fmt` errors on a file, show the
error - it usually points at a real syntax problem.
