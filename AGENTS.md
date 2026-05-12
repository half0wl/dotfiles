# AGENTS.md

## Repository

This is Ray's personal macOS dotfiles and workstation bootstrap repo.

The main entrypoint is `setup.sh`, which configures macOS defaults, installs
Homebrew/Nix/language tooling, and symlinks files from `conf/` and `nvim/` into
`$HOME`.

## Working rules

- Treat this repo as personal infrastructure. Small mistakes can affect Ray's
  machine, shell, editor, Git, Claude, and Pi agent setup.
- Read the relevant config or script before changing it. Do not infer behavior
  from filenames alone.
- Keep changes targeted. Avoid broad formatting or preference cleanup unless
  explicitly requested.
- Prefer clear, boring shell over clever shell.
- Preserve idempotency in setup code. Re-running `./setup.sh <hostname>` or
  `./setup.sh pi` should not leave broken symlinks or duplicate state.
- Be careful with destructive commands in scripts. Any `rm`, `sudo`, `chown`,
  or system-default change must be intentional and easy to audit.

## Layout

- `setup.sh` — full macOS bootstrap plus the `pi` subcommand.
- `_lib.sh` — shared shell helpers for setup output and behavior.
- `conf/` — home-directory configuration files and app/agent configs.
- `conf/claude/` — Claude Code settings, hooks, skills, and global guidance.
- `conf/pi/` — Pi agent settings, themes, extensions, and system guidance.
- `nvim/` — Neovim/LazyVim configuration.
- `docs/` — supporting documentation assets.

## Style

- Shell scripts use Bash with `set -eou pipefail` where appropriate.
- Use quoted variables unless word splitting is required.
- Keep user-facing output consistent with existing `write_info`, `write_ok`,
  `write_warn`, and related helpers.
- Do not add dependencies to the bootstrap lists casually. Explain why a tool
  belongs in a fresh-machine install.
