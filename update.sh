#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

git pull --ff-only

if command -v pi >/dev/null; then
  pi update --all
fi

printf '\nDotfiles updated. Restart Neovim and pi to load changes.\n'
