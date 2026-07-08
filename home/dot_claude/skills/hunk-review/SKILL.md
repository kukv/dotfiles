---
name: hunk-review
description: Interacts with live Hunk diff review sessions via CLI. Inspects review focus, navigates files and hunks, reloads session contents, and adds inline review comments. Use when the user has a Hunk session running or wants to review diffs interactively.
---

# Hunk Review (loader)

This is a thin loader for the real Hunk review skill bundled with the installed
`hunk` binary. Because `hunk` is installed via mise, the bundled skill path
changes on every version upgrade — so resolve it at runtime instead of pinning
a path.

## Steps

1. Run `hunk skill path` to print the absolute path of the bundled skill file.
2. Read that file with the Read tool.
3. Follow its instructions to carry out the user's request.

If `hunk skill path` fails (e.g. `hunk` is not installed), tell the user and
suggest installing it via mise (`mise install`), then stop.
