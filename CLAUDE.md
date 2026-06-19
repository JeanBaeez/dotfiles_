# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal dotfiles for a zsh + Neovim + tmux setup, designed to be bootstrapped onto fresh Linux VMs with one command. Supports **apt** (Debian/Ubuntu/Kali), **dnf** (Fedora/RHEL/Rocky/Alma), and **pacman** (Arch). There is no build/test/lint toolchain — the "code" is shell config (`.zshrc`), a LazyVim Neovim config (`.config/nvim/`), a tmux config (`.tmux.conf.local`), and an installer (`bootstrap.sh`).

## Working in this repo

The edit/deploy loop is: edit files here, commit, push, then on each VM run `cd ~/dotfiles && git pull && ./bootstrap.sh`. `bootstrap.sh` is idempotent and safe to re-run (it backs up existing dotfiles to `*.bak.<timestamp>` before overwriting).

Validate changes before committing:
- `bash -n bootstrap.sh` — syntax-check the installer (it uses `set -euo pipefail`).
- `nvim --headless "+Lazy! sync" +qa` — sync/validate Neovim plugins (what bootstrap runs).
- Lua is formatted with `stylua` per `.config/nvim/stylua.toml` (2-space indent, 120 cols, double quotes): `stylua .config/nvim/`.

There is no way to "run tests." To actually exercise a change, run `./bootstrap.sh` on a throwaway VM (or test the installer in two modes — see below).

## bootstrap.sh architecture

A single bash script that runs in two modes, controlled by who invokes it:
- **As regular user**: installs for `$USER`, uses `sudo` internally for apt/chsh.
- **As root / via sudo**: installs dotfiles for `$SUDO_USER` (override with `TARGET_USER=alice`), then `chown`s everything back to that user.

Key abstractions to preserve when editing:
- `TARGET_USER` / `TARGET_HOME` resolution at the top drives everything — files land in `$TARGET_HOME`, not necessarily the invoker's home.
- `$SUDO` is `""` when already root, else `"sudo"` — prefix privileged commands with it.
- `run_as_target` runs a command as the target user (used for per-user config like git and nvim plugin sync).
- `backup_then_copy` handles the backup-before-overwrite logic.

Package management is abstracted across distros:
- `PM` is detected as `apt`/`dnf`/`pacman`.
- `pm_update_upgrade` runs the OS-appropriate update **and** upgrade.
- `pm_install pkg...` installs the OS-appropriate way.
- `PACKAGES` is set from a per-`PM` `case` block because package names differ (e.g. `fd-find`/`fd`, `dnsutils`/`bind-utils`/`bind`, `mtr-tiny`/`mtr`, `gh`/`github-cli`, `tldr`/`tealdeer`). On dnf it also enables EPEL.

Beyond packages it: clones **Oh My Tmux!** (`gpakosz/.tmux`) and installs the vendored `.tmux.conf.local`; fetches **Neovim** and **lazygit** from upstream GitHub release tarballs (distro Neovim is too old for LazyVim, which needs ≥ 0.11.2); `chsh`'s to zsh; and configures git to use `delta`.

When adding a CLI tool: add it to **every** `PM` arm of the `PACKAGES` `case` (mind the per-distro name), or if it isn't packaged (like lazygit/nvim) add an upstream-download install function following the existing arch-detection pattern (`x86_64`/`aarch64`). Then update the README and the final "Goodies" log lines.

## Neovim config (`.config/nvim/`)

Standard LazyVim layout. `lua/config/lazy.lua` declares the LazyVim base plus enabled `extras` (TypeScript, JSON, markdown, tailwind, eslint, prettier). Per-plugin overrides live in `lua/plugins/*.lua`; `disabled.lua` turns plugins off. `lazy-lock.json` pins plugin versions — commit it when intentionally updating plugins. AI tooling (`plugins/ai.lua`) wires up copilot.lua and an optional mcphub.nvim.

## tmux config

Uses [Oh My Tmux!](https://github.com/gpakosz/.tmux). The large upstream `.tmux.conf` is **not** vendored — `bootstrap.sh` clones it to `~/.tmux` and symlinks `~/.tmux.conf` to it (re-runs `git pull` to update). Only `.tmux.conf.local` (the user-customization file) lives in this repo; edit that for tmux changes, never the symlinked `.tmux.conf`.

## .zshrc notes

The `.zshrc` is Kali-flavored and pentest-oriented. Two things to be aware of:
- The top section has hardcoded user-specific paths (e.g. `/home/c0l1nr00t/.config/bin/target` in `settarget`/`cleartarget`) and references to scripts that may not exist on a given host (`/usr/bin/whichSystem.py`, `enhanced-scanner.py`). These are personal/legacy and are not installed by `bootstrap.sh`.
- The portable, bootstrap-relevant additions are in the `# ----- goodies -----` section at the bottom (zoxide, direnv, `fd`→`fdfind` alias, `lg`→lazygit). Put new shell wiring there.
