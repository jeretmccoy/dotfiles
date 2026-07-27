# Instructions for AI Coding Agents

These instructions apply to every change in this repository.

## Publishing changes

- After completing and validating requested configuration changes, commit and push them unless the user says not to.
- Use a short, ordinary commit message describing the change.
- Do not add AI attribution anywhere: no `Co-authored-by` trailer, generated-by notice, assistant name, model name, badge, or similar text.
- Do not alter the user's Git name, email, signing configuration, or authorship settings.
- Never force-push or rewrite published history unless the user explicitly requests it.

## Privacy and security

This is a public repository. Before every commit and push, inspect both staged and untracked files for information that should not be public.

Never commit:

- Passwords, API keys, access tokens, OAuth data, cookies, credentials, or private keys
- `.env` files, Pi authentication files, sessions, usage ledgers, or generated account data
- Private database URLs or connection details
- Private hostnames, IP addresses, SSH usernames, SSH key paths, or internal service names
- Personal filesystem paths, device names, email addresses, or other identifying information
- Private project, client, employer, workspace, or repository names and paths

Use generic placeholders and documented local override files for machine-specific or private values. Do not print secret values while checking files. Prefer listing suspicious file names and matching line numbers. If a possible leak cannot be safely resolved, stop before committing or pushing and ask the user.

## Required pre-push checks

1. Review `git status --short`, including untracked files.
2. Review the complete staged diff with `git diff --cached`.
3. Confirm ignored/private files have not been force-added.
4. Search tracked and staged content for credentials, personal absolute paths, private hosts/IPs, and identifying project names.
5. Run relevant syntax or startup checks for files changed.
6. Push only after all checks pass.
