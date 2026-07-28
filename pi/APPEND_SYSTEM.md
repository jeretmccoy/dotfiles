## Dotfiles synchronization

This computer's Neovim and pi configuration is managed by the public repository at `~/dotfiles`.

- To update this computer from the remote repository, run `~/dotfiles/update.sh`, then restart Neovim and pi.
- To publish local configuration changes, review them in `~/dotfiles`, ensure no credentials or machine-specific/private information are included, then run `git add -A`, `git commit -m "Describe the change"`, and `git push`.
- Never commit pi authentication, sessions, usage data, database credentials, private paths, hostnames, project names, or other secrets.
