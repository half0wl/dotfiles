#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 02-nvidia.sh
#
# NVIDIA open kernel driver from NVIDIA's CUDA repo, built by DKMS for
# every installed kernel and signed for Secure Boot. Does nothing on a
# machine without an NVIDIA GPU.
#
# Usage:
#   ./02-nvidia.sh [--dry-run] [--yes]
#
# Notes:
#   * Headers follow every new kernel (linux-headers-amd64), so DKMS can
#     rebuild the module on kernel upgrades.
#   * With Secure Boot on, the DKMS signing key (/var/lib/dkms/mok.pub)
#     must be enrolled once: set a one-time password here, then on the
#     next boot pick Enroll MOK -> Continue -> Yes -> password -> Reboot in
#     MOK Manager.
#   * Exits non-zero if any kernel lacks a loadable module: don't boot it.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

NVIDIA_REPO="https://developer.download.nvidia.com/compute/cuda/repos"
NVIDIA_REPO+="/debian13/x86_64"
KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
MOK_KEY=/var/lib/dkms/mok.pub

# The driver, plus the kernel/header metapackages so headers follow
# every new kernel.
DRIVER_PACKAGES=(
  nvidia-open
  linux-image-amd64
  linux-headers-amd64
)

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

PROBLEMS=0
MOK_PENDING=0
SECURE_BOOT=0
KERNELS=()

detect_gpu() {
  step "GPU"
  require_cmd lspci mokutil
  # Capture instead of `| grep -q`: under pipefail an early grep exit can
  # fail the pipeline.
  local gpu
  gpu=$(lspci | grep -Ei '(vga|3d).*nvidia' | head -n1 || true)
  if [[ -z $gpu ]]; then
    skip "no NVIDIA GPU found; nothing to do"
    exit 0
  fi
  ok "NVIDIA GPU: ${gpu#*: }"
  local sb
  sb=$(mokutil --sb-state 2>/dev/null || true)
  if [[ $sb == *"SecureBoot enabled"* ]]; then
    SECURE_BOOT=1
    info "Secure Boot is on"
  else
    info "Secure Boot is off"
  fi
}

install_driver() {
  step "Driver"
  if pkg_installed cuda-keyring; then
    skip "cuda-keyring already installed"
  else
    deb_ensure cuda-keyring "$NVIDIA_REPO/$KEYRING_DEB"
    apt_update
  fi
  apt_ensure "${DRIVER_PACKAGES[@]}"
}

install_headers() {
  step "Kernel headers"
  mapfile -t KERNELS < <(
    find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' |
      sed 's/^vmlinuz-//' | sort -V
  )
  ((${#KERNELS[@]})) || die "no kernels found in /boot"

  local k
  for k in "${KERNELS[@]}"; do
    if pkg_installed "linux-headers-$k"; then
      skip "headers for $k already installed"
    elif apt-cache show "linux-headers-$k" >/dev/null 2>&1; then
      apt_ensure "linux-headers-$k"
    else
      warn "headers for $k are no longer in the archive (old kernel);" \
        "skipping it"
    fi
  done
}

build_modules() {
  step "DKMS modules"
  local k
  for k in "${KERNELS[@]}"; do
    if /usr/sbin/modinfo -k "$k" nvidia >/dev/null 2>&1; then
      skip "nvidia module already built for $k"
    elif [[ -d /lib/modules/$k/build || -e /usr/src/linux-headers-$k ]]
    then
      apply "dkms: build nvidia for $k" sudo dkms autoinstall -k "$k"
    else
      skip "no headers for $k; cannot build"
    fi
  done
}

enroll_mok() {
  step "Secure Boot key"
  if ((!SECURE_BOOT)); then
    skip "Secure Boot is off; no key enrollment needed"
    return 0
  fi
  if ! sudo test -f "$MOK_KEY"; then
    warn "$MOK_KEY is missing; DKMS modules cannot be signed"
    PROBLEMS=$((PROBLEMS + 1))
    return 0
  fi

  # --test-key exits non-zero when the key IS enrolled: capture, don't
  # pipe.
  local out
  out=$(sudo mokutil --test-key "$MOK_KEY" 2>&1 || true)
  if [[ $out == *"already enrolled"* ]]; then
    skip "DKMS signing key already enrolled"
  elif [[ $out == *"enrollment request"* ]]; then
    skip "DKMS key enrollment already pending;" \
      "finish it in MOK Manager on next boot"
    MOK_PENDING=1
  else
    info "set a one-time password;" \
      "you'll type it again in MOK Manager on reboot"
    apply_tty "mokutil: request enrollment of $MOK_KEY" \
      sudo mokutil --import "$MOK_KEY"
    MOK_PENDING=1
  fi
}

verify_modules() {
  step "Verify"
  local k signer
  for k in "${KERNELS[@]}"; do
    if ! /usr/sbin/modinfo -k "$k" nvidia >/dev/null 2>&1; then
      if ((DRY_RUN)); then
        info "$k: module not built yet (dry run)"
        continue
      fi
      error "$k: no NVIDIA module; do NOT boot this kernel"
      PROBLEMS=$((PROBLEMS + 1))
      continue
    fi
    signer=$(/usr/sbin/modinfo -k "$k" -F signer nvidia 2>/dev/null ||
      true)
    if [[ -n $signer ]]; then
      ok "$k: module present, signed by $signer"
    elif ((SECURE_BOOT)); then
      error "$k: module is unsigned and Secure Boot is on;" \
        "it will not load"
      PROBLEMS=$((PROBLEMS + 1))
    else
      warn "$k: module unsigned (fine only while Secure Boot is off)"
    fi
  done
}

finish() {
  if ((PROBLEMS)); then
    die "$PROBLEMS problem(s) above;" \
      "fix them before booting the affected kernel(s)"
  fi
  # /run/reboot-required: 01-update.sh leaves the reboot for a new kernel
  # to this script, whose own steps may all be skips by then (DKMS builds
  # the module while the kernel installs).
  if ((_N_CHANGED || MOK_PENDING)) || [[ -e /run/reboot-required ]]; then
    ((!DRY_RUN)) || return 0
    step "Next"
    info "reboot, then check the driver with: nvidia-smi"
    if ((MOK_PENDING)); then
      info "MOK Manager on boot: press a key, Enroll MOK -> Continue ->" \
        "Yes -> password -> Reboot"
    fi
  fi
  return 0
}

main() {
  lib_init "NVIDIA driver, DKMS and Secure Boot signing" "$@"
  no_extra_args
  require_user
  need_sudo

  detect_gpu
  install_driver
  install_headers
  build_modules
  enroll_mok
  verify_modules
  finish
}

main "$@"
