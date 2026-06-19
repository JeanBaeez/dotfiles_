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

set -euo pipefail

# --- Resolve target user (whose dotfiles we install) ------------------------
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  TARGET_USER="${TARGET_USER:-${SUDO_USER:-root}}"
else
  TARGET_USER="${TARGET_USER:-$USER}"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
  echo "Could not resolve home directory for user '$TARGET_USER'." >&2
  exit 1
fi
TARGET_GROUP="$(id -gn "$TARGET_USER")"

# sudo wrapper: empty if already root, otherwise 'sudo'
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

# Run a command AS the target user (used for nvim plugin install)
run_as_target() {
  if [[ "$(id -un)" == "$TARGET_USER" ]]; then
    "$@"
  else
    sudo -u "$TARGET_USER" -H "$@"
  fi
}

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

log "Installing for user: $TARGET_USER  (home: $TARGET_HOME)"

# --- 1. Detect package manager ----------------------------------------------
# Supports Debian/Ubuntu/Kali (apt), Fedora/RHEL/Rocky/Alma (dnf), and Arch (pacman).
if command -v apt-get >/dev/null 2>&1; then
  PM="apt"
elif command -v dnf >/dev/null 2>&1; then
  PM="dnf"
elif command -v pacman >/dev/null 2>&1; then
  PM="pacman"
else
  echo "No supported package manager found (need apt, dnf, or pacman). Aborting." >&2
  exit 1
fi
log "Detected package manager: $PM"

# Update package metadata and upgrade installed packages (OS-appropriate).
pm_update_upgrade() {
  case "$PM" in
    apt)    $SUDO apt-get update -y && $SUDO DEBIAN_FRONTEND=noninteractive apt-get upgrade -y ;;
    dnf)    $SUDO dnf -y upgrade --refresh ;;
    pacman) $SUDO pacman -Syu --noconfirm ;;
  esac
}

# Install one or more packages (OS-appropriate).
pm_install() {
  case "$PM" in
    apt)    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
  esac
}

# --- 2. Install packages ----------------------------------------------------
# Package names differ across distros; one curated list per package manager.
# Neovim + lazygit are installed from upstream tarballs below (distro versions
# are often too old — LazyVim needs Neovim >= 0.11.2).
case "$PM" in
  apt)
    PACKAGES=(
      zsh zsh-syntax-highlighting zsh-autosuggestions
      lsd bat fzf ripgrep fd-find jq ncdu tldr
      htop btop
      tmux git git-delta gh zoxide direnv
      dnsutils traceroute mtr-tiny whois net-tools rsync mosh httpie
      age pwgen
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
      curl ca-certificates tar unzip
    )
    ;;
esac

# RHEL-likes need EPEL for many of these tools. Enable it BEFORE the upgrade so
# the refresh below also fetches EPEL's metadata (harmless no-op on Fedora).
if [[ "$PM" == "dnf" ]]; then
  log "Enabling EPEL (for RHEL/Rocky/Alma; no-op on Fedora)"
  $SUDO dnf install -y epel-release || warn "epel-release not available; EPEL-only packages may be skipped"
fi

log "Updating system packages (update + upgrade)"
pm_update_upgrade

log "Installing packages: ${PACKAGES[*]}"
if ! pm_install "${PACKAGES[@]}"; then
  warn "Bulk install failed (likely a missing package on this distro). Retrying one at a time."
  for pkg in "${PACKAGES[@]}"; do
    pm_install "$pkg" || warn "Skipping $pkg (not available)"
  done
fi

# --- 2a. Install lazygit from upstream (not in apt on most distros) ---------
install_lazygit() {
  if command -v lazygit >/dev/null 2>&1; then
    log "lazygit already installed: $(lazygit --version 2>&1 | head -1)"
    return 0
  fi
  local arch lg_arch ver tmpdir url
  arch="$(uname -m)"
  case "$arch" in
    x86_64)         lg_arch="x86_64" ;;
    aarch64|arm64)  lg_arch="arm64" ;;
    *) warn "Unsupported arch '$arch' for lazygit; skipping"; return 0 ;;
  esac
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -oP '"tag_name":\s*"v?\K[^"]+' | head -1)"
  if [[ -z "$ver" ]]; then warn "Could not resolve latest lazygit version; skipping"; return 0; fi
  url="https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${lg_arch}.tar.gz"
  tmpdir="$(mktemp -d)"
  log "Downloading lazygit $ver"
  curl -fsSL "$url" -o "$tmpdir/lazygit.tar.gz"
  tar -C "$tmpdir" -xzf "$tmpdir/lazygit.tar.gz" lazygit
  $SUDO install -m 0755 "$tmpdir/lazygit" /usr/local/bin/lazygit
  rm -rf "$tmpdir"
  log "lazygit installed: $(/usr/local/bin/lazygit --version 2>&1 | head -1)"
}
install_lazygit

# --- 2b. Install latest Neovim from upstream --------------------------------
install_neovim() {
  local arch nvim_arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)         nvim_arch="x86_64" ;;
    aarch64|arm64)  nvim_arch="arm64" ;;
    *) warn "Unsupported arch '$arch' for Neovim binary; skipping"; return 0 ;;
  esac

  local url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz"
  local tmpdir
  tmpdir="$(mktemp -d)"

  log "Downloading Neovim ($nvim_arch) from $url"
  curl -fsSL "$url" -o "$tmpdir/nvim.tar.gz"

  $SUDO rm -rf /opt/nvim
  $SUDO mkdir -p /opt
  $SUDO tar -C /opt -xzf "$tmpdir/nvim.tar.gz"
  $SUDO mv "/opt/nvim-linux-${nvim_arch}" /opt/nvim
  $SUDO ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim

  rm -rf "$tmpdir"
  log "Neovim installed: $(/usr/local/bin/nvim --version | head -1)"
}
install_neovim

# --- 3. Copy dotfiles into place (with backup) ------------------------------
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

# --- 3b. Install tmux config (Oh My Tmux! / gpakosz/.tmux) -------------------
# The 99 KB upstream .tmux.conf is cloned (and updated on re-run) rather than
# vendored; we symlink it and drop our customized .tmux.conf.local on top.
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
install_tmux_config

# --- 4. Make zsh the default shell ------------------------------------------
ZSH_BIN="$(command -v zsh)"
CURRENT_SHELL="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != "$ZSH_BIN" ]]; then
  log "Changing default shell to $ZSH_BIN for $TARGET_USER"
  $SUDO chsh -s "$ZSH_BIN" "$TARGET_USER"
else
  log "Default shell already zsh for $TARGET_USER, skipping chsh"
fi

# --- 4b. Configure git to use delta for diffs (if installed) ----------------
if command -v delta >/dev/null 2>&1; then
  log "Configuring git to use delta as pager (for $TARGET_USER)"
  run_as_target git config --global core.pager 'delta'
  run_as_target git config --global interactive.diffFilter 'delta --color-only'
  run_as_target git config --global delta.navigate true
  run_as_target git config --global merge.conflictstyle zdiff3
fi

# --- 5. Pre-warm nvim plugins (optional, non-fatal) -------------------------
log "Pre-installing nvim plugins (lazy.nvim sync) as $TARGET_USER"
run_as_target nvim --headless "+Lazy! sync" +qa 2>/dev/null || warn "nvim plugin sync failed (will retry on first launch)"

# --- 6. Done ----------------------------------------------------------------
log "Bootstrap complete. Open a new shell or run: exec zsh"
log "tmux: Oh My Tmux! installed — prefix is C-b (and C-a); edit ~/.tmux.conf.local to customize"
log "Goodies: z (zoxide) | lg (lazygit) | fd (fdfind) | direnv | btop/htop | ncdu | jq | tldr <cmd>"
log "Net: dig/host/nslookup | traceroute/mtr | whois | rsync/mosh/httpie | age (encrypt) | pwgen"
log "If lsd/batcat icons look wrong, install a Nerd Font on your terminal."
