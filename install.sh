#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

backup_and_link() {
  local source=$1 target=$2
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$(readlink "$target" 2>/dev/null || true)" = "$source" ]; then
      printf 'Already linked: %s\n' "$target"
      return
    fi
    mkdir -p "$BACKUP_DIR/$(dirname "${target#$HOME/}")"
    mv "$target" "$BACKUP_DIR/${target#$HOME/}"
    printf 'Backed up: %s\n' "$target"
  fi
  ln -s "$source" "$target"
  printf 'Linked: %s -> %s\n' "$target" "$source"
}

if ! command -v git >/dev/null; then
  echo "git is required." >&2
  exit 1
fi

if ! command -v nvim >/dev/null; then
  if command -v brew >/dev/null; then
    brew install neovim
  else
    echo "Note: install Neovim using your operating system's package manager."
  fi
fi

if ! command -v pi >/dev/null; then
  if command -v npm >/dev/null; then
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
  else
    echo "Note: install Node.js/npm, then run:" >&2
    echo "  npm install -g --ignore-scripts @earendil-works/pi-coding-agent" >&2
  fi
fi

backup_and_link "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
backup_and_link "$DOTFILES_DIR/pi/settings.json" "$HOME/.pi/agent/settings.json"
backup_and_link "$DOTFILES_DIR/pi/APPEND_SYSTEM.md" "$HOME/.pi/agent/APPEND_SYSTEM.md"

mkdir -p "$HOME/.pi/agent/extensions"
for extension in "$DOTFILES_DIR"/pi/extensions/*.ts; do
  backup_and_link "$extension" "$HOME/.pi/agent/extensions/$(basename "$extension")"
done

cat <<'MSG'

Installation complete.

Private and generated data remain local and are not linked, including:
  ~/.pi/agent/auth.json
  ~/.pi/agent/sessions/
  ~/.pi/workspaces.json
  ~/.config/nvim-local/dbee.lua

Run `pi`, then `/login`, to authenticate on a new device.
Open `nvim`; lazy.nvim will install plugins automatically.
MSG
