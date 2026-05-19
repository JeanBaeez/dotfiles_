# dotfiles

My shell + nvim setup, bootstrapped onto fresh Debian/Ubuntu/Kali VMs with one command.

## Install

On the target VM, as your regular user:

```bash
git clone <this-repo-url> ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
exec zsh
```

Or with sudo / as root (installs the dotfiles for `$SUDO_USER`, falling back to root):

```bash
sudo ./bootstrap.sh
# or, to target a specific user:
sudo TARGET_USER=alice ./bootstrap.sh
```

The script will:

1. Install apt packages — shell, plugins, and quality-of-life CLI tools:
   - shell: `zsh zsh-syntax-highlighting zsh-autosuggestions`
   - files/text: `lsd bat fzf ripgrep jq ncdu tldr`
   - monitors: `htop btop`
   - dev/git: `tmux git git-delta gh zoxide`
   - base: `curl ca-certificates tar unzip`
2. Download the latest Neovim release tarball from GitHub and install it to `/opt/nvim` (symlink at `/usr/local/bin/nvim`). Apt's `neovim` is too old for LazyVim (needs ≥ 0.11.2).
3. Download the latest `lazygit` release tarball into `/usr/local/bin/lazygit`.
4. Copy `.zshrc` and `.config/nvim/` into your `$HOME` (backups: `.bak.<timestamp>`).
5. `chsh -s $(which zsh)` to make zsh the default shell.
6. Configure git to use `delta` as the diff pager.
7. Run `nvim --headless "+Lazy! sync"` to pre-install plugins.

Goodies you get in the shell:
- `z <dir-fragment>` — jump (zoxide)
- `lg` — lazygit
- `cat` is `batcat`, `ls` is `lsd`
- `delta` powers `git diff` / `git log -p`

It's safe to re-run. Re-running will overwrite the dotfiles (with a fresh backup) and re-install packages (no-op if already installed).

## Running remotely

From a control machine with SSH access to the target:

```bash
ssh user@target 'git clone <repo-url> ~/dotfiles && cd ~/dotfiles && ./bootstrap.sh'
```

## Updating

Edit files locally, commit, push. On each VM:

```bash
cd ~/dotfiles && git pull && ./bootstrap.sh
```

## Caveats

- Default shell change won't take effect inside the current shell session. `exec zsh` or log out/in.
- Icons in `lsd`/`bat` need a Nerd Font installed in the terminal emulator.
- nvim config is [LazyVim](https://www.lazyvim.org/); first launch may take a minute as plugins compile.
- This is currently apt-only (Debian/Ubuntu/Kali). For other distros, extend the package install section in `bootstrap.sh`.
