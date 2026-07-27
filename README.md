# Dotfiles

Portable, public configuration for [Neovim](https://neovim.io/) and [pi](https://pi.dev/).
Credentials, sessions, workspace paths, database connections, and other machine-specific data are intentionally excluded.

## Install

### macOS or Linux

```sh
git clone https://github.com/jeretmccoy/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

The installer backs up existing files under `~/.dotfiles-backup/<timestamp>/` before creating symlinks. It installs Neovim with Homebrew when available and pi with npm when available.

After installation:

```sh
pi
# Run /login inside pi

nvim
# lazy.nvim installs plugins on first launch
```

## Private database configuration

The public Neovim configuration loads an optional database plugin specification from:

```text
~/.config/nvim-local/dbee.lua
```

To configure it on a new machine:

```sh
mkdir -p ~/.config/nvim-local
cp ~/dotfiles/nvim/dbee-local.example.lua ~/.config/nvim-local/dbee.lua
chmod 600 ~/.config/nvim-local/dbee.lua
```

Customize that local file, but do not commit it. Prefer environment variables or a password manager for credentials.

## Update

```sh
~/dotfiles/update.sh
```

Configuration edits made through the symlinked Neovim and pi files appear directly in this repository. Review them, then commit and push:

```sh
cd ~/dotfiles
git status
git add -A
git commit -m "Update configuration"
git push
```

## Not tracked

- Pi authentication and sessions
- Pi usage ledgers and model caches
- Saved workspace names and paths
- Database credentials and connection details
- SSH keys and host configuration

Authenticate pi separately and restore private configuration securely on every device.
