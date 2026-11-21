#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 04-shell.sh
#
# Shell and CLI: zsh as the login shell, the everyday CLI packages, and
# the zsh / git / tmux / neovim / mise configs. Developer tools (neovim,
# tmux, gh, node, ...) come from mise, pinned in conf/mise/config.toml.
#
# Usage:
#   ./04-shell.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   ~/.zshrc ~/.zprofile               zsh/
#   ~/.gitconfig ~/.gitignore_global   git/
#   ~/.config/git/hooks                git/hooks/
#   ~/.tmux.conf ~/.config/tmux/plugins
#   ~/.config/nvim                     nvim/
#   ~/.config/mise/config.toml         mise/
#   ~/.config/gh/config.yml            gh/ (prefs only; auth stays out)
#   ~/.claude/CLAUDE.md                ai/CLAUDE.md (-> AGENTS.md)
#
# Notes:
#   * ~/.zprofile starts Plasma on tty1 (02-system.sh: no display
#     manager).
#   * `mise use -g <tool>` edits conf/mise/config.toml through the link.
#   * GitHub auth is manual: gh auth login && gh auth setup-git.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

PACKAGES=(
  zsh
  zsh-syntax-highlighting
  git
  curl
  socat
  locales
  libfuse2t64
  bubblewrap
  fd-find
  make
  gcc
  ripgrep
  wl-clipboard
  unzip
  gdisk
  parted
  keyutils
  libnotify-bin
  inxi
)

MISE_BIN="$HOME/.local/bin/mise"

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

install_packages() {
  step "Packages"
  apt_ensure "${PACKAGES[@]}"
}

set_login_shell() {
  step "Login shell"
  local zsh current
  zsh=$(command -v zsh || echo /usr/bin/zsh)
  current=$(getent passwd "$USER" | cut -d: -f7)
  if [[ $current == "$zsh" ]]; then
    skip "login shell is already $zsh"
  else
    apply "login shell: $current → $zsh" sudo chsh -s "$zsh" "$USER"
  fi
}

link_configs() {
  step "Configs"
  link_conf zsh/zshrc "$HOME/.zshrc"
  link_conf zsh/zprofile "$HOME/.zprofile"
  link_conf git/gitconfig "$HOME/.gitconfig"
  link_conf git/gitignore_global "$HOME/.gitignore_global"
  link_conf git/hooks "$HOME/.config/git/hooks"
  link_conf tmux/tmux.conf "$HOME/.tmux.conf"
  link_conf tmux/plugins "$HOME/.config/tmux/plugins"
  link_conf nvim "$HOME/.config/nvim"
  link_conf mise/config.toml "$HOME/.config/mise/config.toml"
  link_conf gh/config.yml "$HOME/.config/gh/config.yml"
  link_conf ai/CLAUDE.md "$HOME/.claude/CLAUDE.md"
}

# Run mise from / so no project-local mise.toml is picked up.
mise_at_root() { (cd / && "$MISE_BIN" "$@"); }

install_mise_tools() {
  step "mise"
  local version
  if [[ -x $MISE_BIN ]]; then
    version=$("$MISE_BIN" --version 2>/dev/null | awk '{print $1}')
    skip "mise already installed ($version)"
  else
    apply "install mise (mise.run)" sh -c 'curl -fsSL https://mise.run | sh'
  fi
  if ((DRY_RUN)) && [[ ! -x $MISE_BIN ]]; then
    would "mise install (tools from conf/mise/config.toml)"
    return 0
  fi

  # Read conf/ directly so a dry run (before the link exists) is accurate.
  # --dry-run-code exits 1 when something would be installed.
  export MISE_GLOBAL_CONFIG_FILE="$CONF_DIR/mise/config.toml"
  if mise_at_root install --dry-run-code >/dev/null 2>&1; then
    skip "mise: all tools in conf/mise/config.toml already installed"
    return 0
  fi
  local missing
  missing=$(mise_at_root ls --missing 2>/dev/null |
    awk '{print $1}' | sort -u | paste -sd' ' -)
  apply "mise: install ${missing:-missing tools}" \
    mise_at_root install --yes
}

main() {
  lib_init "zsh, CLI packages, git, tmux, neovim, mise" "$@"
  no_extra_args
  require_user
  need_sudo

  install_packages
  set_login_shell
  link_configs
  install_mise_tools
}

main "$@"
