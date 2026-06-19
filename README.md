# dotfiles

My shell + nvim + tmux setup, bootstrapped onto fresh Linux VMs with one command. Works on Debian/Ubuntu/Kali (apt), Fedora/RHEL/Rocky/Alma (dnf), and Arch (pacman).

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

1. Detect the package manager (apt / dnf / pacman), then **update + upgrade** the system and install shell, plugins, and quality-of-life CLI tools:
   - shell: `zsh zsh-syntax-highlighting zsh-autosuggestions`
   - files/text: `lsd bat fzf ripgrep fd jq ncdu tldr`
   - monitors: `htop btop`
   - dev/git: `tmux git git-delta gh zoxide direnv`
   - networking: dns utils, `traceroute mtr whois net-tools rsync mosh httpie`
   - security/misc: `age pwgen`
   - base: `curl ca-certificates tar unzip`

   (Exact package names are mapped per-distro inside `bootstrap.sh`; on RHEL-likes it also enables EPEL.)
2. Download the latest Neovim release tarball from GitHub and install it to `/opt/nvim` (symlink at `/usr/local/bin/nvim`). Distro `neovim` is usually too old for LazyVim (needs ≥ 0.11.2).
3. Download the latest `lazygit` release tarball into `/usr/local/bin/lazygit`.
4. Install [Oh My Tmux!](https://github.com/gpakosz/.tmux): clone it to `~/.tmux`, symlink `~/.tmux.conf`, and drop our customized `~/.tmux.conf.local` (mouse on, OS clipboard, retain cwd).
5. Copy `.zshrc` and `.config/nvim/` into your `$HOME` (backups: `.bak.<timestamp>`).
6. `chsh -s $(which zsh)` to make zsh the default shell.
7. Configure git to use `delta` as the diff pager.
8. Run `nvim --headless "+Lazy! sync"` to pre-install plugins.

Goodies you get in the shell:
- `z <dir-fragment>` — jump (zoxide)
- `lg` — lazygit
- `cat` is `batcat`, `ls` is `lsd`
- `delta` powers `git diff` / `git log -p`
- `tmux` with Oh My Tmux! — customize via `~/.tmux.conf.local`

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
- Supports apt / dnf / pacman. For another distro, add a `case` arm to the package lists and `pm_*` helpers in `bootstrap.sh`.
- `~/.tmux.conf.local` is yours to edit; `~/.tmux.conf` is a symlink into the upstream clone and is overwritten by `git pull` on re-run.
