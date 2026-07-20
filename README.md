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

1. Detect the package manager (apt / dnf / pacman), then **update + upgrade** the system and install shell, plugins, and quality-of-life CLI tools. Packages install **one-at-a-time behind a live progress bar** (`[####----]  40% (7/17) installing …`) instead of the package manager's default wall of text — on a non-interactive/CI shell it falls back to one clean line per package.
   - shell: `zsh zsh-syntax-highlighting zsh-autosuggestions`
   - files/text: `lsd bat fzf ripgrep fd jq ncdu tldr`
   - monitors: `htop btop`
   - dev/git: `tmux git git-delta gh zoxide direnv`
   - networking: dns utils, `traceroute mtr whois net-tools rsync mosh httpie`
   - security/misc: `age pwgen`
   - fonts: `fontconfig` (`fc-cache`, to register the Nerd Font below)
   - nvim/LazyVim toolchain: `nodejs npm`, a C toolchain (`build-essential`/`gcc`+`make`/`base-devel`), `python3`+`pip`, and `go` — required so Copilot, the LSPs/formatters (Mason), and treesitter parsers actually build on a fresh VM
   - base: `curl ca-certificates tar unzip`

   (Exact package names are mapped per-distro inside `bootstrap.sh`; on RHEL-likes it also enables EPEL.)
2. Download the latest Neovim release tarball from GitHub and install it to `/opt/nvim` (symlink at `/usr/local/bin/nvim`). Distro `neovim` is usually too old for LazyVim (needs ≥ 0.11.2).
3. Download the latest `lazygit` release tarball into `/usr/local/bin/lazygit`.
4. Install the **FiraCode Nerd Font** (ligatures + icon glyphs) per-user into `~/.local/share/fonts` and refresh the font cache. See [Icons & ligatures](#icons--ligatures-nerd-font) — the font must also be selected in your **local** terminal.
5. Install [Oh My Tmux!](https://github.com/gpakosz/.tmux): clone it to `~/.tmux`, symlink `~/.tmux.conf`, and drop our customized `~/.tmux.conf.local` (mouse on, OS clipboard, retain cwd).
6. Copy `.zshrc` and `.config/nvim/` into your `$HOME` (backups: `.bak.<timestamp>`).
7. `chsh -s $(which zsh)` to make zsh the default shell.
8. Configure git to use `delta` as the diff pager.
9. Run `nvim --headless "+Lazy! sync"` to pre-install plugins.

Goodies you get in the shell:
- `z <dir-fragment>` — jump (zoxide)
- `lg` — lazygit
- `cat` is `batcat`, and `ls`/`l`/`ll`/`la`/`lla` are [`lsd`](https://github.com/lsd-rs/lsd) with icons + git status (`lt` = tree view)
- `delta` powers `git diff` / `git log -p`
- `tmux` with Oh My Tmux! — customize via `~/.tmux.conf.local`

It's safe to re-run. Re-running will overwrite the dotfiles (with a fresh backup) and re-install packages (no-op if already installed).

## Icons & ligatures (Nerd Font)

`bootstrap.sh` installs the **FiraCode Nerd Font** on the VM, and the `lsd` aliases (`ll`, `la`, `lla`, …) request icons. But **fonts are rendered by your local terminal emulator, not the remote VM** — so when you SSH in, icons and ligatures only appear if **your local terminal is set to a Nerd Font**. Point it at the same font (either the one bootstrap installed, or install [FiraCode Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/latest) locally):

- **macOS — iTerm2:** Settings → Profiles → Text → Font → *FiraCode Nerd Font*. (Enable "Use ligatures" for `=>`, `!=`, `->`, …)
- **macOS — Terminal.app:** Settings → Profiles → Text → Change… → *FiraCode Nerd Font*. (Terminal.app does **not** render ligatures; icons work.)
- **VS Code integrated terminal:** set `"terminal.integrated.fontFamily": "FiraCode Nerd Font"` (and `"editor.fontLigatures": true` for the editor).
- **Windows Terminal:** Settings → your profile → Appearance → Font face → *FiraCode Nerd Font*.
- **Alacritty / Kitty / WezTerm:** set the font family to `FiraCode Nerd Font` in the respective config.

If `lla` shows tofu boxes (□) or question marks instead of icons, your terminal font is not a Nerd Font.

## Testing

`bootstrap.sh` is refactored function-first with a guarded `main`, so its logic is unit-tested with [bats](https://github.com/bats-core/bats-core) without running any installs:

```bash
bats tests/            # run the suite (brew install bats-core / apt install bats)
bash -n bootstrap.sh   # syntax check
shellcheck bootstrap.sh
```

The tests cover the progress-bar renderer, arch mapping, the per-distro package lists (incl. `fontconfig`), the Nerd Font URL, and the `.zshrc`/README regressions this setup fixes.

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
- Icons in `lsd`/`bat` need a Nerd Font selected in your **local** terminal emulator — see [Icons & ligatures](#icons--ligatures-nerd-font). The VM-side font install alone is not enough over SSH.
- nvim config is [LazyVim](https://www.lazyvim.org/); first launch may take a minute as plugins compile.
- Supports apt / dnf / pacman. For another distro, add a `case` arm to the package lists and `pm_*` helpers in `bootstrap.sh`.
- `~/.tmux.conf.local` is yours to edit; `~/.tmux.conf` is a symlink into the upstream clone and is overwritten by `git pull` on re-run.
