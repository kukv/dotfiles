# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/). Shared between WSL (Linux) and macOS; OS-specific differences are handled with `.tmpl` branching on `.chezmoi.os`.

## Apply

```bash
chezmoi init --apply https://github.com/kukv/dotfiles.git
```

Git identity (`user.name` / `user.email` / signing key) is provided via chezmoi data. On the provisioned machines it is seeded into `~/.config/chezmoi/chezmoi.toml` by the `os-setup` Ansible run; on a manual first run chezmoi prompts for it.

## Machine-local / secret config

Put machine-local environment variables and secrets in `~/.zshrc.local` / `~/.zprofile.local`. These are created once by chezmoi and never overwritten, and are not tracked in this repository.

## Edit

```bash
chezmoi edit ~/.zshrc
chezmoi apply
```

## What lives here

- `~/.zshrc`, `~/.zprofile` (OS-branched), `~/.gitconfig`
- `~/.config/mise/config.toml` (tool versions)
- `~/.config/nvim` (LazyVim, vendored)
- Oh-My-Zsh + plugins/theme (via chezmoi externals, pinned + renovate-tracked)
- macOS only: `~/.ssh/config`, iTerm2 dynamic profile
