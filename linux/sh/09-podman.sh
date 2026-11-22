#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 09-podman.sh
#
# Podman for development containers, rootless, with nothing running at
# boot: Podman has no daemon, and its optional API socket/service and
# timers stay disabled, system-wide and for your user.
#
# Usage:
#   ./09-podman.sh [--dry-run] [--yes]
#
# Notes:
#   * Debian's podman package never enables its units on a fresh install
#     (only re-enables ones you had enabled); this script checks anyway
#     and disables any that are on.
#   * Rootless containers need a subordinate UID/GID range for your user
#     in /etc/subuid and /etc/subgid; one is added if missing.
#   * Want the Docker-compatible API socket on demand? Run
#     `systemctl --user start podman.socket` (not `enable`).

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

PACKAGES=(
  podman
)

# Units that would start Podman things at boot or login.
UNITS=(
  podman.socket
  podman.service
  podman-restart.service
  podman-auto-update.timer
)

# Subordinate ID range for rootless containers (if none is set up yet).
SUB_ID_START=100000
SUB_ID_COUNT=65536

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

install_podman() {
  step "Packages"
  apt_ensure "${PACKAGES[@]}"
}

# is_enabled system|user UNIT
is_enabled() {
  local -a scope=()
  [[ $1 == user ]] && scope=(--user)
  systemctl "${scope[@]}" is-enabled --quiet "$2" 2>/dev/null
}

keep_units_off() {
  step "Nothing at boot"
  local unit scope
  for scope in system user; do
    for unit in "${UNITS[@]}"; do
      if ! is_enabled "$scope" "$unit"; then
        skip "$scope $unit not enabled"
      elif [[ $scope == system ]]; then
        apply "disable $unit (system)" sudo systemctl disable "$unit"
      else
        apply "disable $unit (user)" systemctl --user disable "$unit"
      fi
    done
  done
}

configure_rootless() {
  step "Rootless"
  local file id last=$((SUB_ID_START + SUB_ID_COUNT - 1))
  for file in /etc/subuid /etc/subgid; do
    id=uids
    [[ $file == /etc/subgid ]] && id=gids
    if grep -q "^$USER:" "$file" 2>/dev/null; then
      skip "$file already has a range for $USER"
    else
      apply "$file: $USER:$SUB_ID_START:$SUB_ID_COUNT" \
        sudo usermod "--add-sub$id" "$SUB_ID_START-$last" "$USER"
    fi
  done
}

main() {
  lib_init "Rootless Podman, nothing started at boot" "$@"
  no_extra_args
  require_user
  need_sudo

  install_podman
  keep_units_off
  configure_rootless
}

main "$@"
