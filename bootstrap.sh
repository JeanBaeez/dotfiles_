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

# --- 1. Detect OS / package manager -----------------------------------------
if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script currently supports Debian/Ubuntu/Kali (apt). Aborting." >&2
  exit 1
fi

# --- 2. Install packages ----------------------------------------------------
PACKAGES=(
  # shell + plugins
  zsh
  zsh-syntax-highlighting
  zsh-autosuggestions
  # file/text tooling
  lsd
  bat
  fzf
  ripgrep
  jq
  ncdu
  tldr
  # system monitors
  htop
  btop
  # dev / git / multiplexer
  tmux
  git
  git-delta
  gh
  zoxide
  # base
  curl
  ca-certificates
  tar
  unzip
)
# Neovim is installed from upstream tarball below — apt's version is too old for LazyVim (needs >= 0.11.2).

log "Updating apt and installing packages: ${PACKAGES[*]}"
$SUDO apt-get update -y
if ! $SUDO apt-get install -y "${PACKAGES[@]}"; then
  warn "Bulk install failed (likely a missing package on this distro). Retrying one at a time."
  for pkg in "${PACKAGES[@]}"; do
    $SUDO apt-get install -y "$pkg" || warn "Skipping $pkg (not available)"
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
log "Goodies available: z <dir> (zoxide), lg (lazygit), btop, htop, ncdu, jq, tldr <cmd>, delta (git diff)"
log "If lsd/batcat icons look wrong, install a Nerd Font on your terminal."
