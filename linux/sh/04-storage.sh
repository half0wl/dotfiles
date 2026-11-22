#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 04-storage.sh
#
# SSD housekeeping on the LUKS + LVM layout: pass TRIM through dm-crypt so
# fstrim reaches the SSD (weekly fstrim.timer), and shrink ext4's root
# reserve. Verifies the whole TRIM path at the end. Also adds APFS support
# for Mac-formatted drives.
#
# Usage:
#   ./04-storage.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   /etc/udisks2/mount_options.conf   udisks2/ (APFS mounts in Dolphin)
#
# Notes:
#   * /etc/crypttab holds this machine's volume UUIDs, so it is edited in
#     place (adds `discard`, backup in /etc/crypttab.bak), not symlinked.
#   * Already-unlocked volumes get TRIM without a reboot; cryptsetup asks
#     for the LUKS passphrase of each one that still needs it.
#   * Tradeoff of TRIM on LUKS: someone with the raw disk can see which
#     blocks are unused.
#   * ext4 reserves 5% for root by default (~180G on 3.6T); 1% (~36G)
#     still leaves root room to work when the disk fills up.
#   * APFS: apfs-dkms is the kernel driver (DKMS-built, signed with the
#     same MOK key as 02-nvidia.sh). It mounts read-only unless given
#     `-o readwrite`, and write support is experimental. Dolphin mounts
#     through udisks, which conf/udisks2/mount_options.conf sets to
#     writable and owned by you.
#   * FileVault-encrypted APFS volumes need fsapfsmount (libfsapfs-utils,
#     read-only, FUSE): fsapfsmount -p <password> /dev/sdX2 <dir>
#   * Manual mount: sudo mount -t apfs -o ro[,vol=N] /dev/sdX2 <dir>

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

ROOT_LV=/dev/vg0/root
RESERVED_PCT=1

APFS_PACKAGES=(
  apfs-dkms       # kernel driver: read-only, experimental read-write
  apfsprogs       # mkfs.apfs, fsck.apfs
  libfsapfs-utils # fsapfsmount / fsapfsinfo: FileVault volumes
)

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

VOLUMES=()
PROBLEMS=0

# Matches a `discard` option in a crypttab options field.
HAS_DISCARD='(^|,)discard(,|$)'

read_volumes() {
  [[ -s /etc/crypttab ]] || return 0
  mapfile -t VOLUMES < <(
    awk '!/^[[:space:]]*(#|$)/ && NF >= 3 { print $1 }' /etc/crypttab
  )
}

configure_crypttab() {
  step "crypttab"
  if ((${#VOLUMES[@]} == 0)); then
    skip "no encrypted volumes in /etc/crypttab"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  on_exit "rm -f '$tmp'"
  awk -v re="$HAS_DISCARD" '
    BEGIN { OFS = "\t" }
    /^[[:space:]]*(#|$)/ || NF < 3 { print; next }
    {
      if (NF < 4) $4 = "luks"
      if ($4 !~ re) $4 = $4 ",discard"
      print
    }' /etc/crypttab >"$tmp"

  if cmp -s "$tmp" /etc/crypttab; then
    skip "discard already set for ${VOLUMES[*]}"
    return 0
  fi
  apply "crypttab: back up to /etc/crypttab.bak" \
    sudo cp /etc/crypttab /etc/crypttab.bak
  apply "crypttab: add discard" sudo install -m 644 "$tmp" /etc/crypttab
  apply "rebuild initramfs (all kernels)" sudo update-initramfs -u -k all
}

enable_live_trim() {
  step "Unlocked volumes"
  local name table
  for name in "${VOLUMES[@]}"; do
    table=$(sudo dmsetup table "$name" 2>/dev/null || true)
    if [[ -z $table ]]; then
      skip "$name: not unlocked now; crypttab covers it at next unlock"
    elif [[ $table == *allow_discards* ]]; then
      skip "$name: TRIM already active"
    else
      apply_tty "$name: enable TRIM (enter its LUKS passphrase)" \
        sudo cryptsetup refresh --allow-discards "$name"
    fi
  done
}

# Print a numeric field ("Block count:", ...) from `tune2fs -l` output.
tune2fs_field() { # stats field
  awk -F: -v f="$2" '$1 == f { gsub(/ /, "", $2); print $2 }' <<<"$1"
}

configure_root_reserve() {
  step "ext4 root reserve"
  if [[ ! -e $ROOT_LV ]]; then
    skip "$ROOT_LV not found"
    return 0
  fi
  local stats blocks reserved want was
  stats=$(sudo tune2fs -l "$ROOT_LV")
  blocks=$(tune2fs_field "$stats" "Block count")
  reserved=$(tune2fs_field "$stats" "Reserved block count")
  want=$((blocks * RESERVED_PCT / 100))
  was=$(((reserved * 100 + blocks / 2) / blocks)) # rounded
  if ((reserved == want)); then
    skip "$ROOT_LV already reserves ${RESERVED_PCT}%" \
      "($reserved blocks)"
  else
    apply "$ROOT_LV: reserve ${RESERVED_PCT}% for root (was ${was}%)" \
      sudo tune2fs -m "$RESERVED_PCT" "$ROOT_LV"
  fi
}

check_crypttab() {
  local name
  for name in "${VOLUMES[@]}"; do
    if awk -v n="$name" -v re="$HAS_DISCARD" \
      '$1 == n && $4 ~ re { f = 1 } END { exit !f }' /etc/crypttab; then
      ok "crypttab: $name has discard"
    else
      error "crypttab: $name is missing discard"
      PROBLEMS=$((PROBLEMS + 1))
    fi
  done
}

# The crypttab copy inside the initramfs is what's used at boot.
check_initramfs() {
  ((${#VOLUMES[@]})) || return 0
  local initrd work boot_ct
  initrd="/boot/initrd.img-$(uname -r)"
  work=$(sudo mktemp -d)
  on_exit "sudo rm -rf '$work'"
  busy "unpack $initrd" sudo unmkinitramfs "$initrd" "$work"
  boot_ct=$(sudo find "$work" -path '*cryptroot/crypttab' -print -quit)
  if [[ -n $boot_ct ]] &&
    sudo grep -qE '(^|[[:space:],])discard(,|[[:space:]]|$)' "$boot_ct"
  then
    ok "initramfs: boot-time crypttab has discard"
  else
    error "initramfs: boot-time crypttab is missing discard" \
      "(sudo update-initramfs -u -k all)"
    PROBLEMS=$((PROBLEMS + 1))
  fi
}

check_live_volumes() {
  local name table gran max
  for name in "${VOLUMES[@]}"; do
    table=$(sudo dmsetup table "$name" 2>/dev/null || true)
    if [[ -z $table ]]; then
      skip "$name: not unlocked"
      continue
    fi
    if [[ $table == *allow_discards* ]]; then
      ok "dm-crypt: $name passes discards"
    else
      error "dm-crypt: $name does not pass discards"
      PROBLEMS=$((PROBLEMS + 1))
    fi
    read -r gran max < <(
      lsblk -dnbo DISC-GRAN,DISC-MAX "/dev/mapper/$name"
    )
    if ((${gran:-0} > 0 && ${max:-0} > 0)); then
      ok "lsblk: $name advertises discard"
    else
      error "lsblk: $name does not advertise discard"
      PROBLEMS=$((PROBLEMS + 1))
    fi
  done
}

verify_trim() {
  step "Verify TRIM"
  systemd_enable fstrim.timer --now
  ((DRY_RUN)) && return 0
  check_crypttab
  check_initramfs
  check_live_volumes
  ((PROBLEMS == 0)) || die "$PROBLEMS TRIM check(s) failed"
}

# Built for the running kernel and loadable (fails on an unsigned module
# with Secure Boot on).
install_apfs() {
  step "APFS"
  apt_ensure "${APFS_PACKAGES[@]}"
  link_conf udisks2/mount_options.conf /etc/udisks2/mount_options.conf
  ((DRY_RUN)) && return 0

  local k
  k=$(uname -r)
  if ! /usr/sbin/modinfo -k "$k" apfs >/dev/null 2>&1; then
    warn "apfs module not built for $k" \
      "(headers missing? sudo dkms autoinstall)"
    return 0
  fi
  if sudo modprobe apfs 2>/dev/null; then
    ok "apfs module loads on $k"
  else
    warn "apfs module will not load on $k; with Secure Boot on, enroll" \
      "the DKMS MOK key (02-nvidia.sh) and reboot"
  fi
}

main() {
  lib_init "TRIM through LUKS, ext4 root reserve, APFS" "$@"
  no_extra_args
  require_user
  need_sudo

  read_volumes
  configure_crypttab
  enable_live_trim
  configure_root_reserve
  verify_trim
  install_apfs
}

main "$@"
