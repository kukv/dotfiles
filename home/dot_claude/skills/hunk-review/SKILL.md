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
3. Follow its instructions to carry out the user's request, subject to the
   local policy below.

If `hunk skill path` fails (e.g. `hunk` is not installed), tell the user and
suggest installing it via mise (`mise install`), then stop.

## Local policy

These rules sit on top of the bundled skill and take precedence for this setup
(herdr split panes: Claude Code in one pane, Hunk in another, often several
worktree tabs open at once). Keep exact command syntax deferred to the bundled
skill; the rules below only constrain how you select and drive a session.

### Session selection (multi-tab safety)

Never hijack a sibling tab's Hunk window. Pin the session for THIS worktree:

- Select every `hunk session` command with `--repo "$(git rev-parse --show-toplevel)"`
  (never a bare command, never `--repo .`).
- If several sessions share that repo root, run `hunk session list --json`,
  pick the `sessionId` whose `repoRoot` matches (disambiguate by
  `terminal.locations[].tty`), and pass `<session-id>` on every command.
- Never rely on auto-resolve when more than one session is live.

### Showing changes on request

The user launches Hunk themselves in the split pane (e.g. `hunk show --watch`),
then asks you to make changes viewable. Do NOT launch Hunk yourself — reload
their live session with the bundled skill's `reload` command, selecting it with
the worktree `--repo` above:

- Working-tree changes: reload with `-- diff`
- A commit or range: reload with `-- show <ref>` / `-- diff <range>`

Then navigate to the first hunk worth their attention.
