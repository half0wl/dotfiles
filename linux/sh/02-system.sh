#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 02-system.sh
#
# System policy: automatic security updates that never remove kernels or
# reboot on their own, a deny-incoming firewall, TTY login (Plasma starts
# from ~/.zprofile on tty1, no display manager), en_US.UTF-8, and the
# motherboard's onboard Bluetooth adapter switched off. Only that one
# device is disabled: Bluetooth itself stays on and other adapters (e.g.
# a USB dongle) keep working.
#
# Usage:
#   ./02-system.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   /etc/apt/apt.conf.d/20auto-upgrades     unattended-upgrades on
#   /etc/apt/apt.conf.d/99keep-all-kernels  never autoremove kernels
#   /etc/udev/rules.d/81-disable-onboard-bt.rules   onboard adapter off
#
# Notes:
#   * Not config files, so applied as commands (each checked first): ufw,
#     systemd default target, /etc/locale.gen + update-locale.
#   * Re-enable the onboard Bluetooth adapter: remove the udev link above
#     and reboot.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

LOCALE=en_US.UTF-8

UPDATE_PACKAGES=(
  unattended-upgrades
  apt-listchanges
)

# Onboard Bluetooth adapter to disable (the B850I's Realtek, a USB device
# on the motherboard). Only this vendor:product is deauthorized; the
# Bluetooth stack and any other adapter are left alone.
BT_VENDOR=0bda
BT_PRODUCT=8922

# Warn when /boot is fuller than this (every kept kernel uses some).
BOOT_WARN_PCT=80

APT_CONF=/etc/apt/apt.conf.d
UDEV_SRC=udev/81-disable-onboard-bt.rules
UDEV_RULE=/etc/udev/rules.d/81-disable-onboard-bt.rules

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

configure_apt() {
  step "Automatic updates"
  apt_ensure "${UPDATE_PACKAGES[@]}"
  link_conf apt/apt.conf.d/20auto-upgrades "$APT_CONF/20auto-upgrades"
  link_conf apt/apt.conf.d/99keep-all-kernels \
    "$APT_CONF/99keep-all-kernels"

  ((DRY_RUN)) && return 0
  local dump uu='Unattended-Upgrade'
  dump=$(apt-config dump)
  if [[ $dump == *"$uu::Remove-Unused-Kernel-Packages \"false\""* ]]; then
    ok "unattended-upgrades will not remove kernels"
  else
    warn "another apt config overrides Remove-Unused-Kernel-Packages:"
    grep -rn 'Remove-Unused-Kernel-Packages' "$APT_CONF/" |
      sed 's/^/        /' || true
  fi
  if [[ $dump == *"$uu::Automatic-Reboot \"true\""* ]]; then
    warn "unattended-upgrades is set to reboot automatically;" \
      "check $APT_CONF/"
  else
    ok "unattended-upgrades will not reboot on its own"
  fi
  local remv
  remv=$(apt-get -s autoremove 2>/dev/null |
    grep -E '^Remv linux-(image|headers|kbuild)' || true)
  if [[ -z $remv ]]; then
    ok "apt autoremove will not remove any kernel packages"
  else
    warn "apt autoremove would still remove kernel packages:"
    detail "$remv"
  fi
}

report_boot_space() {
  step "/boot space"
  local img k size use
  for img in $(find /boot -maxdepth 1 -name 'vmlinuz-*' | sort -V); do
    k=${img#/boot/vmlinuz-}
    size=$(du -ch /boot/*-"$k" 2>/dev/null | tail -n1 | cut -f1)
    detail "$(printf '%-32s %s' "$k" "$size")"
  done
  use=$(df --output=pcent /boot | tail -n1 | tr -dc '0-9')
  if ((use > BOOT_WARN_PCT)); then
    warn "/boot is ${use}% full; purge an old kernel:" \
      "sudo apt purge linux-image-<ver> linux-headers-<ver>"
  else
    ok "/boot is ${use}% full"
  fi
}

configure_firewall() {
  step "Firewall"
  apt_ensure ufw
  local status
  status=$(sudo ufw status verbose 2>/dev/null || true)
  if [[ $status == *"deny (incoming)"* ]]; then
    skip "ufw: incoming already denied by default"
  else
    apply "ufw: deny incoming by default" \
      sudo ufw default deny incoming
  fi
  if [[ $status == *"allow (outgoing)"* ]]; then
    skip "ufw: outgoing already allowed by default"
  else
    apply "ufw: allow outgoing by default" \
      sudo ufw default allow outgoing
  fi
  if [[ $status == *"Status: active"* ]]; then
    skip "ufw already active"
  else
    apply "ufw: enable" sudo ufw --force enable
  fi
}

configure_login() {
  step "Login"
  # Plasma is started from ~/.zprofile on tty1 (see 04-shell.sh), so no
  # display manager.
  if systemctl is-enabled --quiet sddm 2>/dev/null; then
    apply "disable sddm" sudo systemctl disable sddm
  else
    skip "sddm already disabled"
  fi
  if [[ $(systemctl get-default) == multi-user.target ]]; then
    skip "default target is already multi-user.target"
  else
    apply "boot to multi-user.target (TTY login)" \
      sudo systemctl set-default multi-user.target
  fi
}

configure_locale() {
  step "Locale"
  local escaped=${LOCALE//./\\.}
  if grep -qE "^${escaped} " /etc/locale.gen; then
    skip "$LOCALE already enabled in /etc/locale.gen"
  else
    apply "enable $LOCALE in /etc/locale.gen" \
      sudo sed -i "s/^# *${escaped} /${LOCALE} /" /etc/locale.gen
  fi
  local norm=${LOCALE,,}
  norm=${norm//-/}
  if grep -qix "$norm" <<<"$(command locale -a 2>/dev/null)"; then
    skip "$LOCALE already generated"
  else
    apply "locale-gen" sudo locale-gen
  fi
  if grep -qx "LANG=$LOCALE" /etc/default/locale 2>/dev/null; then
    skip "LANG=$LOCALE already the system default"
  else
    apply "update-locale LANG=$LOCALE" \
      sudo update-locale "LANG=$LOCALE"
  fi
}

# Only the onboard adapter; Bluetooth and other adapters stay on.
disable_onboard_bluetooth() {
  step "Onboard Bluetooth adapter"
  LINK_CHANGED=0
  link_conf "$UDEV_SRC" "$UDEV_RULE"
  if ((LINK_CHANGED)); then
    apply "reload udev rules" sudo udevadm control --reload
  fi

  # The rule only acts on "add"; deauthorize the onboard adapter if it is
  # up right now.
  local dev name id="$BT_VENDOR:$BT_PRODUCT" found=0
  for dev in /sys/bus/usb/devices/*; do
    [[ -r $dev/idVendor && -r $dev/idProduct ]] || continue
    [[ $(<"$dev/idVendor"):$(<"$dev/idProduct") == "$id" ]] || continue
    found=1
    name=$(basename "$dev")
    if [[ $(<"$dev/authorized") == 0 ]]; then
      skip "onboard adapter $id ($name) already disabled"
    else
      apply "disable onboard adapter $id ($name)" \
        sudo sh -c "echo 0 > '$dev/authorized'"
    fi
  done
  ((found)) || skip "onboard adapter $id not present"
}

main() {
  lib_init "Updates, firewall, login, locale, onboard Bluetooth" "$@"
  no_extra_args
  require_user
  need_sudo

  configure_apt
  report_boot_space
  configure_firewall
  configure_login
  configure_locale
  disable_onboard_bluetooth
}

main "$@"
