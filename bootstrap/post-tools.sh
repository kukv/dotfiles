#!/bin/sh
# Setup that needs tools from [tools]. Runs as the `bootstrap` task (last step of
# mise bootstrap) on every run; keep it idempotent.
set -eu

# corepack shims in node's bin shadow the pnpm / yarn that mise manages, and
# mise's npm backend then picks the wrong pnpm (ERR_PNPM_NO_GLOBAL_BIN_DIR).
for shim in "$HOME"/.local/share/mise/installs/node/*/bin/pnpm; do
  if [ -e "$shim" ]; then
    mise exec node -- corepack disable
    break
  fi
done

# herdr plugins: "<plugin_id> <repo>". Install dir layout differs across herdr
# versions, so ask herdr what is installed. kukv.github-dash (moved to the
# octoscope tool) and official.browser (deprecated upstream) no longer ship a
# plugin manifest and cannot be installed.
while read -r id repo; do
  herdr plugin list 2>/dev/null | grep -q "^- $id " || herdr plugin install "$repo" --yes </dev/null
done <<'EOT'
herdr-file-viewer smarzban/herdr-file-viewer
hunk.diff edmundmiller/herdr-plugin-hunk
EOT

# Claude Code skills: "<skill> <repo>". hunk-review is intentionally absent:
# the self-made loader in ~/.claude/skills/hunk-review (chezmoi) matches the
# mise-managed npm:hunkdiff version.
while read -r name repo; do
  [ -e "$HOME/.claude/skills/$name" ] ||
    skills add "$repo" --skill "$name" --agent claude-code --global --yes </dev/null
done <<'EOT'
herdr herdrdev/herdr
find-skills vercel-labs/skills
ax yusukebe/ax
ast-grep ast-grep/agent-skill
ast-grep-outline ast-grep/agent-skill
EOT

# Claude Code CLI (self-updating; install once).
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
