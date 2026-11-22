#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 06-keyd.sh
#
# macOS-style keyboard with keyd: Cmd = Ctrl (plus Mac overrides), Option
# = word-wise movement, Caps Lock = Esc, and per-app overrides through
# keyd-application-mapper (started at login by Plasma's autostart).
#
# Usage:
#   ./06-keyd.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   ~/.config/keyd/default.conf      keyd/default.conf
#   /etc/keyd/default.conf           -> ~/.config/keyd/default.conf
#   ~/.config/keyd/app.conf          keyd/app.conf (per-app overrides)
#   ~/.config/autostart/keyd-application-mapper.desktop
#
# Notes:
#   * Debian names the binary keyd.rvaiya; /usr/local/bin/keyd links to
#     it.
#   * keyd-application-mapper needs your user in the `keyd` group: log out
#     and back in after this script adds you.
#   * keyd reads /etc/keyd as root; the link means editing the conf/ file
#     is enough (then: sudo keyd reload).

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

KEYD_TAG=v2.5.0 # matches Debian 13's keyd package
MAPPER_URL="https://raw.githubusercontent.com/rvaiya/keyd/$KEYD_TAG"
MAPPER_URL+="/scripts/keyd-application-mapper"
MAPPER_BIN=/usr/local/bin/keyd-application-mapper

KEYD_HOME="$HOME/.config/keyd"
AUTOSTART="$HOME/.config/autostart/keyd-application-mapper.desktop"

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

_install_mapper() {
  local tmp
  tmp=$(mktemp)
  curl -fsSL -o "$tmp" "$MAPPER_URL"
  sudo install -m 755 "$tmp" "$MAPPER_BIN"
  rm -f -- "$tmp"
}

install_keyd() {
  step "keyd"
  apt_ensure keyd
  ensure_link /usr/bin/keyd.rvaiya /usr/local/bin/keyd
  if [[ -x $MAPPER_BIN ]]; then
    skip "keyd-application-mapper already installed"
  else
    apply "install keyd-application-mapper ($KEYD_TAG)" _install_mapper
  fi
}

link_configs() {
  step "Configs"
  LINK_CHANGED=0
  link_conf keyd/default.conf "$KEYD_HOME/default.conf"
  ensure_link "$KEYD_HOME/default.conf" /etc/keyd/default.conf
  local daemon_conf_changed=$LINK_CHANGED
  link_conf keyd/app.conf "$KEYD_HOME/app.conf"
  link_conf keyd/keyd-application-mapper.desktop "$AUTOSTART"

  if ((daemon_conf_changed)) && systemctl is-active --quiet keyd; then
    apply "keyd: reload config" sudo keyd.rvaiya reload
  fi
}

configure_access() {
  step "Service and group"
  systemd_enable keyd --now
  if grep -qx keyd <<<"$(id -nG "$USER" | tr ' ' '\n')"; then
    skip "$USER already in group keyd"
  else
    apply "add $USER to group keyd" sudo usermod -aG keyd "$USER"
    warn "log out and back in so keyd-application-mapper can talk to" \
      "keyd"
  fi
}

main() {
  lib_init "macOS-style keys with keyd" "$@"
  no_extra_args
  require_user
  need_sudo

  install_keyd
  link_configs
  configure_access
}

main "$@"
