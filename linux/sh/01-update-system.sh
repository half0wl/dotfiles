#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 01-update-system.sh
#
# After 00-set-default-dirs.sh on a fresh install: sanity checks, a full
# system upgrade, the base packages every later script relies on, and
# firmware updates. With an NVIDIA GPU, run 02-install-nvidia-drivers.sh
# next and reboot after it: it builds and checks the driver for any
# kernel this upgrade installed. Otherwise reboot when it asks you to.
#
# Usage:
#   ./01-update-system.sh [--dry-run] [--yes]
#
# Notes:
#   * On an up-to-date machine this is a no-op: upgrades, autoremove and
#     firmware are only applied when something is pending.
#   * fwupdmgr asks before flashing each device (unless --yes).
#   * Headers for the running kernel can be missing right after an upgrade
#     pulled in a newer kernel; reboot into it and re-run.
#
# Packages:
#   linux-headers-amd64     headers that follow every new kernel, so DKMS
#                           can build modules for it
#   linux-headers-<kernel>  headers for the running kernel
#   dkms                    builds kernel modules (NVIDIA, APFS)
#   mokutil, keyutils       Secure Boot key enrollment and signing
#   pciutils                lspci, to detect the GPU
#   curl, wget              downloads
#   ca-certificates         trusted CAs for those downloads
#   gnupg                   apt repo signing keys
#   git                     this repo
#   python3                 helpers inside several scripts
#   fwupd                   firmware updates (fwupdmgr)

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

BASE_PACKAGES=(
  linux-headers-amd64
  dkms
  mokutil
  keyutils
  pciutils
  curl
  wget
  ca-certificates
  gnupg
  git
  python3
  fwupd
)

# Keep local versions of config files on upgrades (many are symlinks into
# conf/), instead of prompting.
APT_UPGRADE_OPTS=(
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
)

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

check_system() {
  step "System"
  require_debian13
  ok "Debian 13 (trixie), kernel $(uname -r)"
  getent hosts deb.debian.org >/dev/null ||
    die "no network (deb.debian.org does not resolve)"
  ok "network: deb.debian.org resolves"
}

upgrade_packages() {
  step "Packages"
  # Refreshing the lists is not a change to the system, and the pending
  # upgrade count below needs fresh lists (in dry-run mode too).
  busy "apt: refresh package lists" sudo apt-get update

  local pending
  pending=$(apt-get -s "${APT_UPGRADE_OPTS[@]}" full-upgrade 2>/dev/null |
    grep -c '^Inst ' || true)
  if ((pending == 0)); then
    skip "apt: system is up to date"
  else
    apply "apt: full-upgrade ($pending packages)" \
      sudo DEBIAN_FRONTEND=noninteractive \
      apt-get -y "${APT_UPGRADE_OPTS[@]}" full-upgrade
  fi

  apt_ensure "${BASE_PACKAGES[@]}"

  local headers
  headers="linux-headers-$(uname -r)"
  if pkg_installed "$headers"; then
    skip "apt: $headers already installed"
  elif apt-cache show "$headers" >/dev/null 2>&1; then
    apt_ensure "$headers"
  else
    warn "$headers is not available;" \
      "reboot into the newest kernel and re-run"
  fi

  local removable
  removable=$(apt-get -s autoremove 2>/dev/null | grep -c '^Remv ' || true)
  if ((removable == 0)); then
    skip "apt: nothing to autoremove"
  else
    apply "apt: autoremove ($removable packages)" \
      sudo DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
  fi
}

update_firmware() {
  step "Firmware"
  busy "firmware: refresh metadata" sudo fwupdmgr refresh --force

  # get-updates exits 0 when updates are available, 2 when there is
  # nothing to do.
  local rc=0
  sudo fwupdmgr get-updates --no-unreported-check >/dev/null 2>&1 ||
    rc=$?
  case $rc in
    2) skip "firmware is up to date" ;;
    0)
      local -a yes=()
      ((ASSUME_YES)) && yes=(-y)
      apply_tty "firmware: install updates" \
        sudo fwupdmgr update "${yes[@]}"
      ;;
    *)
      warn "checking for firmware updates failed (exit $rc);" \
        "run 'fwupdmgr get-updates' to see why"
      ;;
  esac
}

offer_reboot() {
  step "Reboot"
  if ((_N_CHANGED == 0)) && [[ ! -e /run/reboot-required ]]; then
    skip "nothing changed; no reboot needed"
    return 0
  fi
  # 02-install-nvidia-drivers.sh builds and checks the driver for every
  # kernel in /boot, including one this run just installed. Rebooting
  # first could start that kernel without a working driver (no graphical
  # session).
  if have lspci && grep -qEi '(vga|3d).*nvidia' <<<"$(lspci)"; then
    warn "NVIDIA GPU: run 02-install-nvidia-drivers.sh next, then reboot"
    return 0
  fi
  if ((DRY_RUN)); then
    would "reboot"
    return 0
  fi
  if confirm "Reboot now?"; then
    info "rebooting"
    sudo systemctl reboot
  fi
}

main() {
  lib_init "Upgrade, base packages and firmware" "$@"
  no_extra_args
  require_user
  need_sudo

  check_system
  upgrade_packages
  update_firmware
  offer_reboot
}

main "$@"
