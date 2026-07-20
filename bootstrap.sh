#!/usr/bin/env bash
# Bootstrap a fresh VM with my shell + nvim setup.
#
# Works in two modes:
#   1. As your regular user:   ./bootstrap.sh           (uses sudo internally for apt + chsh)
#   2. With sudo / as root:    sudo ./bootstrap.sh      (installs dotfiles for $SUDO_USER)
#                              sudo -E ./bootstrap.sh   (same, preserves env)
#
# Override target user (when running as root and SUDO_USER isn't set):
#   sudo TARGET_USER=alice ./bootstrap.sh
#
# The script is structured function-first with a guarded `main` at the bottom so
# the unit tests in tests/ can source it and exercise individual functions
# without triggering any of the install side effects.

# --- Paths / constants (side-effect free; safe to evaluate on `source`) ------
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# --- Target-user resolution --------------------------------------------------
# Sets TARGET_USER / TARGET_HOME / TARGET_GROUP and the $SUDO wrapper
# (empty when already root, "sudo" otherwise).
resolve_target() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    TARGET_USER="${TARGET_USER:-${SUDO_USER:-root}}"
    SUDO=""
  else
    TARGET_USER="${TARGET_USER:-$USER}"
    SUDO="sudo"
  fi

  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
  if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "Could not resolve home directory for user '$TARGET_USER'." >&2
    exit 1
  fi
  TARGET_GROUP="$(id -gn "$TARGET_USER")"
}

# Run a command AS the target user (used for per-user config + nvim plugin sync)
run_as_target() {
  if [[ "$(id -un)" == "$TARGET_USER" ]]; then
    "$@"
  else
    sudo -u "$TARGET_USER" -H "$@"
  fi
}

# --- Package manager abstraction --------------------------------------------
# Supports Debian/Ubuntu/Kali (apt), Fedora/RHEL/Rocky/Alma (dnf), and Arch (pacman).
# Echoes the detected manager, or returns non-zero if none is supported.
detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  else
    return 1
  fi
}

# Update package metadata and upgrade installed packages (OS-appropriate).
pm_update_upgrade() {
  case "$PM" in
    apt)    $SUDO apt-get update -y && $SUDO DEBIAN_FRONTEND=noninteractive apt-get upgrade -y ;;
    dnf)    $SUDO dnf -y upgrade --refresh ;;
    pacman) $SUDO pacman -Syu --noconfirm ;;
  esac
}

# Install one or more packages (OS-appropriate). Quiet-ish so the progress bar
# in install_with_progress stays legible; callers capture output as needed.
pm_install() {
  case "$PM" in
    apt)    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
  esac
}

# Populate the global PACKAGES array for a given package manager. Package names
# differ across distros; one curated list per manager. Neovim + lazygit are
# installed from upstream tarballs (distro versions are often too old — LazyVim
# needs Neovim >= 0.11.2).
set_packages() {
  local pm="$1"
  case "$pm" in
    apt)
      PACKAGES=(
        zsh zsh-syntax-highlighting zsh-autosuggestions
        lsd bat fzf ripgrep fd-find jq ncdu tldr
        htop btop
        tmux git git-delta gh zoxide direnv
        dnsutils traceroute mtr-tiny whois net-tools rsync mosh httpie
        age pwgen
        # fontconfig: fc-cache, used to register the FiraCode Nerd Font (icons/ligatures)
        fontconfig
        # neovim/LazyVim toolchain: copilot + node LSPs/formatters, treesitter
        # parser compilation (C toolchain), python & go language support
        nodejs npm build-essential python3 python3-pip python3-venv golang-go
        curl ca-certificates tar unzip
      )
      ;;
    dnf)
      PACKAGES=(
        zsh zsh-syntax-highlighting zsh-autosuggestions
        lsd bat fzf ripgrep fd-find jq ncdu tealdeer
        htop btop
        tmux git git-delta gh zoxide direnv
        bind-utils traceroute mtr whois net-tools rsync mosh httpie
        age pwgen
        # fontconfig: fc-cache, used to register the FiraCode Nerd Font (icons/ligatures)
        fontconfig
        # neovim/LazyVim toolchain (copilot + LSPs, treesitter, python & go)
        nodejs npm gcc gcc-c++ make python3 python3-pip golang
        curl ca-certificates tar unzip
      )
      ;;
    pacman)
      PACKAGES=(
        zsh zsh-syntax-highlighting zsh-autosuggestions
        lsd bat fzf ripgrep fd jq ncdu tealdeer
        htop btop
        tmux git git-delta github-cli zoxide direnv
        bind traceroute mtr whois net-tools rsync mosh httpie
        age pwgen
        # fontconfig: fc-cache, used to register the FiraCode Nerd Font (icons/ligatures)
        fontconfig
        # neovim/LazyVim toolchain (copilot + LSPs, treesitter, python & go)
        nodejs npm base-devel python python-pip go
        curl ca-certificates tar unzip
      )
      ;;
    *)
      echo "set_packages: unknown package manager '$pm'" >&2
      return 1
      ;;
  esac
}

# --- Progress UI -------------------------------------------------------------
# Pure, deterministic bar string: "[####--------]  33% (1/3)".
# Avoids `seq` (mishandles the zero-fill case) by width-padding with printf and
# substituting the padding — this makes the function trivially unit-testable.
progress_bar_string() {
  local current="$1" total="$2" width="${3:-28}"
  (( total <= 0 )) && total=1
  (( current < 0 )) && current=0
  (( current > total )) && current="$total"
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local pct=$(( current * 100 / total ))
  local fbar ebar
  fbar="$(printf '%*s' "$filled" '')"; fbar="${fbar// /#}"
  ebar="$(printf '%*s' "$empty" '')";  ebar="${ebar// /-}"
  printf '[%s%s] %3d%% (%d/%d)' "$fbar" "$ebar" "$pct" "$current" "$total"
}

# Install packages one-at-a-time behind a live progress bar instead of the
# package manager's default wall of text. On a TTY it redraws a single line; when
# piped/CI it prints one clean line per package. Failures are collected and
# reported at the end rather than aborting the whole bootstrap.
install_with_progress() {
  local -a pkgs=("$@")
  local total="${#pkgs[@]}" i=0 pkg
  local -a failed=()
  local logf tty=0
  logf="$(mktemp)"
  [[ -t 1 ]] && tty=1
  (( total == 0 )) && { rm -f "$logf"; return 0; }

  for pkg in "${pkgs[@]}"; do
    if [[ "$tty" -eq 1 ]]; then
      printf '\r\033[1;34m==>\033[0m %s  installing %-24s\033[K' \
        "$(progress_bar_string "$i" "$total")" "$pkg"
    fi
    if ! pm_install "$pkg" >>"$logf" 2>&1; then
      failed+=("$pkg")
    fi
    i=$((i + 1))
    if [[ "$tty" -eq 1 ]]; then
      printf '\r\033[1;34m==>\033[0m %s  %-24s\033[K' \
        "$(progress_bar_string "$i" "$total")" ""
    else
      printf '==> [%d/%d] %s\n' "$i" "$total" "$pkg"
    fi
  done
  [[ "$tty" -eq 1 ]] && printf '\n'

  if (( ${#failed[@]} > 0 )); then
    warn "Some packages could not be installed: ${failed[*]}"
    warn "Install log kept at: $logf"
  else
    rm -f "$logf"
  fi
}

# --- Arch mapping ------------------------------------------------------------
# Normalizes `uname -m` to the release-asset naming used by the upstream
# lazygit/Neovim tarballs. Accepts an explicit arch (for tests) or reads uname.
map_arch() {
  local m="${1:-$(uname -m)}"
  case "$m" in
    x86_64|amd64)  echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) return 1 ;;
  esac
}

# --- Nerd Font URL -----------------------------------------------------------
# Upstream ryanoasis/nerd-fonts per-font zip. Split out for unit testing.
nerd_font_url() {
  local font="${1:-FiraCode}"
  echo "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip"
}

# --- Upstream installers -----------------------------------------------------
# lazygit (not packaged on most distros).
install_lazygit() {
  if command -v lazygit >/dev/null 2>&1; then
    log "lazygit already installed: $(lazygit --version 2>&1 | head -1)"
    return 0
  fi
  local lg_arch ver tmpdir url
  if ! lg_arch="$(map_arch)"; then
    warn "Unsupported arch '$(uname -m)' for lazygit; skipping"; return 0
  fi
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -oP '"tag_name":\s*"v?\K[^"]+' | head -1)"
  if [[ -z "$ver" ]]; then warn "Could not resolve latest lazygit version; skipping"; return 0; fi
  url="https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${lg_arch}.tar.gz"
  tmpdir="$(mktemp -d)"
  log "Downloading lazygit $ver"
  # Catch download/extract failures explicitly so a network hiccup skips lazygit
  # instead of aborting the whole bootstrap, and so $tmpdir is always cleaned up.
  if curl -fsSL "$url" -o "$tmpdir/lazygit.tar.gz" \
     && tar -C "$tmpdir" -xzf "$tmpdir/lazygit.tar.gz" lazygit; then
    $SUDO install -m 0755 "$tmpdir/lazygit" /usr/local/bin/lazygit
    log "lazygit installed: $(/usr/local/bin/lazygit --version 2>&1 | head -1)"
  else
    warn "lazygit download/extract failed; skipping"
  fi
  rm -rf "$tmpdir"
}

# Latest Neovim from upstream (distro Neovim is too old for LazyVim).
install_neovim() {
  local nvim_arch url tmpdir
  if ! nvim_arch="$(map_arch)"; then
    warn "Unsupported arch '$(uname -m)' for Neovim binary; skipping"; return 0
  fi

  url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz"
  tmpdir="$(mktemp -d)"
  log "Downloading Neovim ($nvim_arch) from $url"
  # Catch the download explicitly (the flaky, network-bound step) so a hiccup
  # skips Neovim rather than aborting the bootstrap, and $tmpdir is cleaned up.
  if curl -fsSL "$url" -o "$tmpdir/nvim.tar.gz"; then
    $SUDO rm -rf /opt/nvim
    $SUDO mkdir -p /opt
    $SUDO tar -C /opt -xzf "$tmpdir/nvim.tar.gz"
    $SUDO mv "/opt/nvim-linux-${nvim_arch}" /opt/nvim
    $SUDO ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
    log "Neovim installed: $(/usr/local/bin/nvim --version | head -1)"
  else
    warn "Neovim download failed; skipping (LazyVim needs Neovim >= 0.11.2 — re-run to retry)"
  fi
  rm -rf "$tmpdir"
}

# Reclaim ownership of the ~/.local tree that a root-for-user `mkdir -p` may have
# created as root, so the target user can later create nvim data/state dirs.
# Non-recursive on the parents to avoid clobbering unrelated pre-existing
# subtrees. Tolerant of failures (a purely cosmetic font step must never abort
# the whole bootstrap) and a no-op when we're already the target user.
reclaim_local_ownership() {
  [[ "$TARGET_USER" != "$(id -un)" ]] || return 0
  chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.local/share/fonts" 2>/dev/null || true
  [[ -d "$TARGET_HOME/.local/share" ]] && chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.local/share" 2>/dev/null || true
  [[ -d "$TARGET_HOME/.local" ]] && chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.local" 2>/dev/null || true
  return 0
}

# FiraCode Nerd Font — provides programming ligatures and the icon glyphs that
# lsd/bat use. Installed per-user into ~/.local/share/fonts and registered with
# fc-cache. NOTE: fonts render in the *client* terminal emulator; on a headless
# VM this mainly helps X/Wayland sessions. To see icons over SSH you must also
# set your local terminal to a Nerd Font — see the README.
install_nerd_font() {
  local font_dir="$TARGET_HOME/.local/share/fonts/FiraCodeNerdFont"
  if [[ -d "$font_dir" ]] && compgen -G "$font_dir/*.ttf" >/dev/null 2>&1; then
    log "FiraCode Nerd Font already installed ($font_dir)"
    return 0
  fi
  if ! command -v fc-cache >/dev/null 2>&1; then
    warn "fontconfig (fc-cache) not available; skipping Nerd Font install"
    return 0
  fi

  local url tmpdir
  url="$(nerd_font_url FiraCode)"
  tmpdir="$(mktemp -d)"
  log "Downloading FiraCode Nerd Font"
  # Chain the fallible steps; on any failure warn and fall through to cleanup.
  # `mkdir -p "$font_dir"` may create ~/.local[/share] as root in the sudo path,
  # so reclaim_local_ownership + tmpdir cleanup run on EVERY exit path below —
  # explicitly (no RETURN trap, which would surprisingly re-fire on main's return).
  if curl -fsSL "$url" -o "$tmpdir/FiraCode.zip" \
     && mkdir -p "$font_dir" \
     && unzip -o -q "$tmpdir/FiraCode.zip" -d "$tmpdir/extract" \
     && find "$tmpdir/extract" -type f -name '*.ttf' -exec cp -f {} "$font_dir/" \; ; then
    reclaim_local_ownership
    run_as_target fc-cache -f "$font_dir" >/dev/null 2>&1 || fc-cache -f >/dev/null 2>&1 || true
    log "FiraCode Nerd Font installed ($font_dir)"
  else
    warn "FiraCode Nerd Font install failed; skipping (icons/ligatures unaffected on the client terminal)"
    reclaim_local_ownership
  fi
  rm -rf "$tmpdir"
}

# --- Dotfiles copy -----------------------------------------------------------
backup_then_copy() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    log "Backing up existing $dst -> ${dst}.bak.${TIMESTAMP}"
    mv "$dst" "${dst}.bak.${TIMESTAMP}"
  elif [[ -L "$dst" ]]; then
    rm "$dst"
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" ]]; then
    cp -r "$src" "$dst"
  else
    cp "$src" "$dst"
  fi
}

# tmux config (Oh My Tmux! / gpakosz/.tmux). The 99 KB upstream .tmux.conf is
# cloned (and updated on re-run) rather than vendored; we symlink it and drop our
# customized .tmux.conf.local on top.
install_tmux_config() {
  local omt="$TARGET_HOME/.tmux"
  if [[ -d "$omt/.git" ]]; then
    log "Updating Oh My Tmux! in $omt"
    run_as_target git -C "$omt" pull --ff-only || warn "tmux config update failed (keeping existing)"
  else
    log "Cloning Oh My Tmux! into $omt"
    # -e is false for a dangling symlink, so also test -L to catch broken links.
    [[ -e "$omt" || -L "$omt" ]] && mv "$omt" "${omt}.bak.${TIMESTAMP}"
    if ! run_as_target git clone --depth 1 https://github.com/gpakosz/.tmux.git "$omt"; then
      warn "tmux config clone failed; skipping tmux setup"
      return 0
    fi
  fi
  # Back up a pre-existing real ~/.tmux.conf (not a symlink) before we replace it.
  if [[ -e "$TARGET_HOME/.tmux.conf" && ! -L "$TARGET_HOME/.tmux.conf" ]]; then
    log "Backing up existing $TARGET_HOME/.tmux.conf -> .bak.${TIMESTAMP}"
    mv "$TARGET_HOME/.tmux.conf" "$TARGET_HOME/.tmux.conf.bak.${TIMESTAMP}"
  fi
  run_as_target ln -sf "$omt/.tmux.conf" "$TARGET_HOME/.tmux.conf"
  backup_then_copy "$DOTFILES_DIR/.tmux.conf.local" "$TARGET_HOME/.tmux.conf.local"
  if [[ "$TARGET_USER" != "$(id -un)" ]]; then
    chown -h "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.tmux.conf"
    chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.tmux.conf.local"
    chown -R "$TARGET_USER:$TARGET_GROUP" "$omt"
  fi
  log "tmux config installed (~/.tmux.conf -> $omt/.tmux.conf, local at ~/.tmux.conf.local)"
}

# --- Orchestration -----------------------------------------------------------
main() {
  set -euo pipefail

  resolve_target
  log "Installing for user: $TARGET_USER  (home: $TARGET_HOME)"

  # 1. Detect package manager
  if ! PM="$(detect_pm)"; then
    echo "No supported package manager found (need apt, dnf, or pacman). Aborting." >&2
    exit 1
  fi
  log "Detected package manager: $PM"

  # 2. Package list (with EPEL on RHEL-likes)
  set_packages "$PM"

  # RHEL-likes need EPEL for many of these tools. Enable it BEFORE the upgrade so
  # the refresh below also fetches EPEL's metadata (harmless no-op on Fedora).
  if [[ "$PM" == "dnf" ]]; then
    log "Enabling EPEL (for RHEL/Rocky/Alma; no-op on Fedora)"
    $SUDO dnf install -y epel-release || warn "epel-release not available; EPEL-only packages may be skipped"
  fi

  log "Updating system packages (update + upgrade)"
  pm_update_upgrade

  log "Installing ${#PACKAGES[@]} packages (with progress)"
  install_with_progress "${PACKAGES[@]}"

  # 2a/2b/2c. Upstream installs
  install_lazygit
  install_neovim
  install_nerd_font

  # 3. Copy dotfiles into place (with backup)
  log "Installing .zshrc"
  backup_then_copy "$DOTFILES_DIR/.zshrc" "$TARGET_HOME/.zshrc"

  log "Installing nvim config"
  backup_then_copy "$DOTFILES_DIR/.config/nvim" "$TARGET_HOME/.config/nvim"

  # Fix ownership if we wrote files as root for a non-root target user
  if [[ "$TARGET_USER" != "$(id -un)" ]]; then
    log "Fixing ownership: $TARGET_USER:$TARGET_GROUP"
    chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.zshrc"
    chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.config/nvim"
    # parent .config dir might have been created by us as root
    [[ -d "$TARGET_HOME/.config" ]] && chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.config" || true
  fi

  # 3b. tmux config
  install_tmux_config

  # 4. Make zsh the default shell
  local zsh_bin current_shell
  zsh_bin="$(command -v zsh)"
  current_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
  if [[ "$current_shell" != "$zsh_bin" ]]; then
    log "Changing default shell to $zsh_bin for $TARGET_USER"
    $SUDO chsh -s "$zsh_bin" "$TARGET_USER"
  else
    log "Default shell already zsh for $TARGET_USER, skipping chsh"
  fi

  # 4b. Configure git to use delta for diffs (if installed)
  if command -v delta >/dev/null 2>&1; then
    log "Configuring git to use delta as pager (for $TARGET_USER)"
    run_as_target git config --global core.pager 'delta'
    run_as_target git config --global interactive.diffFilter 'delta --color-only'
    run_as_target git config --global delta.navigate true
    run_as_target git config --global merge.conflictstyle zdiff3
  fi

  # 5. Pre-warm nvim plugins (optional, non-fatal)
  log "Pre-installing nvim plugins (lazy.nvim sync) as $TARGET_USER"
  run_as_target nvim --headless "+Lazy! sync" +qa 2>/dev/null || warn "nvim plugin sync failed (will retry on first launch)"

  # 6. Done
  log "Bootstrap complete. Open a new shell or run: exec zsh"
  log "tmux: Oh My Tmux! installed — prefix is C-b (and C-a); edit ~/.tmux.conf.local to customize"
  log "Goodies: z (zoxide) | lg (lazygit) | fd (fdfind) | direnv | btop/htop | ncdu | jq | tldr <cmd>"
  log "Net: dig/host/nslookup | traceroute/mtr | whois | rsync/mosh/httpie | age (encrypt) | pwgen"
  log "Icons: FiraCode Nerd Font installed on this box; set your LOCAL terminal font to"
  log "       'FiraCode Nerd Font' so lsd/lla icons + ligatures render (see README)."
}

# Run only when executed directly, not when sourced by the tests.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
