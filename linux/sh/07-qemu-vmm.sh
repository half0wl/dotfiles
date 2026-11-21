#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 07-qemu-vmm.sh
#
# Incus with QEMU, for development containers and VMs: installs both,
# runs Incus' minimal init (a `dir` storage pool and the incusbr0 bridge),
# adds your user to incus-admin, and opens ufw just enough for guests on
# the bridge.
#
# Usage:
#   ./07-qemu-vmm.sh [--dry-run] [--yes]
#
# Notes:
#   * Log out and back in after the first run, so the incus-admin group
#     applies and `incus` works without sudo.
#   * ufw (02-system.sh) owns the firewall, so Incus' own firewall rules
#     are turned off for the bridge, and ufw lets guests reach the host
#     only for DHCP and DNS, and route out to anywhere. This follows the
#     Incus docs (howto/network_bridge_firewalld, "Use another firewall").
#   * Each ufw rule is checked with `ufw --dry-run` first, which reports a
#     rule it already has instead of adding it again.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

PACKAGES=(
  incus
  qemu-system-x86
)

BRIDGE=incusbr0

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

# True if the minimal init already ran (default pool + bridge exist).
initialized() {
  sudo incus storage show default >/dev/null 2>&1 &&
    sudo incus network show "$BRIDGE" >/dev/null 2>&1
}

# ufw_ensure RULE... -- add a ufw rule unless ufw already has it.
ufw_ensure() {
  local out
  out=$(sudo ufw --dry-run "$@" 2>&1 || true)
  if [[ $out == *"Skipping adding existing rule"* &&
    $out != *"Rules updated"* ]]; then
    skip "ufw: $* already present"
  else
    apply "ufw: $*" sudo ufw "$@"
  fi
}

# The bridge's network, e.g. 10.1.2.1/24 -> 10.1.2.0/24 ("" if off).
bridge_cidr() { # ipv4|ipv6
  local addr
  addr=$(sudo incus network get "$BRIDGE" "$1.address" 2>/dev/null ||
    true)
  local ip=${addr%/*} mask=${addr#*/}
  case $addr in
    "" | none) ;;
    *:*) printf '%s:/%s\n' "${ip%:*}" "$mask" ;;
    *) printf '%s.0/%s\n' "${ip%.*}" "$mask" ;;
  esac
}

install_incus() {
  step "Packages"
  apt_ensure "${PACKAGES[@]}"
}

init_incus() {
  step "Incus"
  if ((DRY_RUN)) && ! have incus; then
    would "incus admin init --minimal"
    return 0
  fi
  if initialized; then
    skip "incus already initialized"
  else
    apply "incus admin init --minimal" sudo incus admin init --minimal
  fi

  if grep -qx incus-admin <<<"$(id -nG "$USER" | tr ' ' '\n')"; then
    skip "$USER already in group incus-admin"
  else
    apply "add $USER to group incus-admin" \
      sudo usermod -aG incus-admin "$USER"
    warn "log out and back in to use incus without sudo"
  fi
}

configure_firewall() {
  step "Firewall ($BRIDGE)"
  if ((DRY_RUN)) && ! { have incus && initialized; }; then
    would "turn off Incus' firewall on $BRIDGE and add ufw rules"
    return 0
  fi

  # ufw owns the firewall: turn Incus' own rules off for the bridge.
  local fam cur cidr
  for fam in ipv4 ipv6; do
    cur=$(sudo incus network get "$BRIDGE" "$fam.firewall" 2>/dev/null ||
      true)
    if [[ $cur == false ]]; then
      skip "$BRIDGE $fam.firewall = false"
    else
      apply "$BRIDGE $fam.firewall = false" \
        sudo incus network set "$BRIDGE" "$fam.firewall=false"
    fi
  done

  # Guests may reach the host only for DHCP (v4/v6) and DNS...
  ufw_ensure allow in on "$BRIDGE" to any port 67 proto udp
  ufw_ensure allow in on "$BRIDGE" to any port 547 proto udp
  ufw_ensure allow in on "$BRIDGE" to any port 53
  # ...and route out to anywhere.
  for fam in ipv4 ipv6; do
    cidr=$(bridge_cidr "$fam")
    if [[ -z $cidr ]]; then
      skip "$BRIDGE has no $fam network"
      continue
    fi
    ufw_ensure route allow in on "$BRIDGE" from "$cidr"
  done
}

main() {
  lib_init "Incus + QEMU for development containers and VMs" "$@"
  no_extra_args
  require_user
  need_sudo

  install_incus
  init_incus
  configure_firewall
}

main "$@"
