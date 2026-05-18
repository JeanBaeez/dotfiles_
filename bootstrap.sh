#!/usr/bin/env bash
# Bootstrap a fresh VM with my shell + nvim setup.
# Run as the regular user (NOT with sudo). The script uses sudo internally where needed.
#
# Usage:
#   git clone <this-repo> ~/dotfiles && cd ~/dotfiles && ./bootstrap.sh
#   or:  curl -fsSL <raw-url>/bootstrap.sh | bash  (less ideal; prefer the clone path)

set -euo pipefail

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "Run this script as your regular user, not root. It uses sudo internally." >&2
  exit 1
fi

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# --- 1. Detect OS / package manager -----------------------------------------
if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script currently supports Debian/Ubuntu/Kali (apt). Aborting." >&2
  exit 1
fi

# --- 2. Install packages ----------------------------------------------------
PACKAGES=(
  zsh
  zsh-syntax-highlighting
  zsh-autosuggestions
  lsd
  bat
  fzf
  ripgrep
  neovim
  git
  curl
  ca-certificates
)

log "Updating apt and installing packages: ${PACKAGES[*]}"
sudo apt-get update -y
sudo apt-get install -y "${PACKAGES[@]}"

# --- 3. Copy dotfiles into place (with backup) ------------------------------
backup_then_copy() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    log "Backing up existing $dst -> ${dst}.bak.${TIMESTAMP}"
    mv "$dst" "${dst}.bak.${TIMESTAMP}"
  elif [[ -L "$dst" ]]; then
    rm "$dst"
  fi
  if [[ -d "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -r "$src" "$dst"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
}

log "Installing .zshrc"
backup_then_copy "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"

log "Installing nvim config"
backup_then_copy "$DOTFILES_DIR/.config/nvim" "$HOME/.config/nvim"

# --- 4. Make zsh the default shell ------------------------------------------
ZSH_BIN="$(command -v zsh)"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != "$ZSH_BIN" ]]; then
  log "Changing default shell to $ZSH_BIN (you may be prompted for your password)"
  sudo chsh -s "$ZSH_BIN" "$USER"
else
  log "Default shell already zsh, skipping chsh"
fi

# --- 5. Pre-warm nvim plugins (optional, non-fatal) -------------------------
log "Pre-installing nvim plugins (lazy.nvim sync)"
nvim --headless "+Lazy! sync" +qa 2>/dev/null || warn "nvim plugin sync failed (will retry on first launch)"

# --- 6. Done ----------------------------------------------------------------
log "Bootstrap complete. Open a new shell or run: exec zsh"
log "If lsd/batcat icons look wrong, install a Nerd Font on your terminal."
