#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 06-zsh.sh
#
# zsh as the login shell, with its configs. Everything else for the
# terminal (git, tmux, neovim, mise, ...) is in 07-dev-toolshed.sh.
#
# Usage:
#   ./06-zsh.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   ~/.zshrc ~/.zprofile   zsh/
#
# Notes:
#   * ~/.zprofile starts Plasma on tty1 (03-config-system.sh: no display
#     manager).
#   * ~/.zshrc activates mise once 07-dev-toolshed.sh has installed it.
#   * The new login shell applies from the next login.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

PACKAGES=(
  zsh
  zsh-syntax-highlighting
)

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
}

main() {
  lib_init "zsh as the login shell" "$@"
  no_extra_args
  require_user
  need_sudo

  install_packages
  set_login_shell
  link_configs
}

main "$@"
