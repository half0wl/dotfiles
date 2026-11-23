#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# kernels.sh
#
# List the kernels on this machine and purge the ones you pick. Each line
# shows a kernel's state, what is special about it, and the space it
# takes in /boot and /lib/modules; the right pane has the details.
#
# Usage:
#   ./etc/kernels.sh
#
# Keys:
#   Up / Down         move
#   Tab / Shift-Tab   select / unselect
#   Ctrl-X            purge the selected kernels (or the highlighted one;
#                     shows what apt would remove and asks first)
#   Esc               quit
#
# Notes:
#   * Never purges the running kernel, nor the one linux-image-amd64
#     depends on: removing that would take the metapackage too, and with
#     it all future kernel updates.
#   * A purge takes the kernel's image and headers, plus their -common and
#     kbuild packages. The kernel's own hooks update GRUB and DKMS.
#   * "leftover" lines are /lib/modules folders of kernels whose packages
#     are gone (files DKMS left behind); purging one removes the folder.
#   * 99keep-all-kernels keeps every kernel ever installed, so /boot only
#     shrinks through here; 03-config-system.sh warns once it is 80% full.
#   * Needs fzf (from mise, 07-dev-toolshed.sh). Run it as yourself: it
#     asks for sudo only to purge.

set -euo pipefail

PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH:/usr/sbin:/sbin"
SELF=$(readlink -f -- "$0")
META=linux-image-amd64

die() {
  echo "kernels: $*" >&2
  exit 1
}

usage() {
  awk 'NR < 4 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
    "$SELF"
  exit 0
}

# dpkg's two-letter state of a package ("ii", "rc", ...), or nothing.
pkg_status() {
  dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | tr -d ' ' ||
    true
}

# Every kernel release dpkg knows a linux-image package for, plus any
# /lib/modules folder, oldest first.
releases() {
  {
    dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' 2>/dev/null |
      sed -n 's/^linux-image-//p' | grep -v -e '-dbg$' -e '-unsigned$' ||
      true
    find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
      2>/dev/null || true
  } | sort -uV
}

# The release the linux-image-amd64 metapackage depends on (the newest).
meta_target() {
  dpkg-query -W -f='${Depends}' "$META" 2>/dev/null |
    grep -oE 'linux-image-[0-9][^ ,]*' | awk 'NR == 1' |
    sed 's/^linux-image-//' || true
}

state() { # release -> installed | config left | leftover | gone
  case $(pkg_status "linux-image-$1") in
    ii*) echo installed ;;
    rc*) echo "config left" ;;
    *)
      if [[ -d /lib/modules/$1 ]]; then echo leftover; else echo gone; fi
      ;;
  esac
}

# The packages a purge of RELEASE takes: whichever of these dpkg has
# installed or still has config for.
packages_for() { # release
  local base=${1%-*} p s
  for p in "linux-image-$1" "linux-image-$1-unsigned" "linux-headers-$1" \
    "linux-headers-$base-common" "linux-kbuild-$base"; do
    s=$(pkg_status "$p")
    if [[ $s == i* || $s == rc* ]]; then echo "$p"; fi
  done
}

size_of() { du -sch -- "$@" 2>/dev/null | awk 'END { print $1 }' || true; }

boot_files() { # release
  local -a files
  shopt -s nullglob
  files=(/boot/*-"$1")
  shopt -u nullglob
  printf '%s\n' "${files[@]}"
}

# One line per kernel: "release <TAB> what fzf shows". The first line is
# the column header.
list_rows() {
  local k st boot mods notes running meta
  local -a files
  running=$(uname -r)
  meta=$(meta_target)
  printf '\t%-28s %-12s %7s %8s  %s\n' RELEASE STATE /boot MODULES NOTES
  while IFS= read -r k; do
    st=$(state "$k")
    [[ $st != gone ]] || continue
    mapfile -t files < <(boot_files "$k")
    boot=-
    if [[ -n ${files[0]:-} ]]; then boot=$(size_of "${files[@]}"); fi
    mods=-
    if [[ -d /lib/modules/$k ]]; then mods=$(size_of "/lib/modules/$k"); fi
    notes=""
    if [[ $k == "$running" ]]; then notes+="running · "; fi
    if [[ $k == "$meta" ]]; then notes+="newest ($META) · "; fi
    printf '%s\t%-28s %-12s %7s %8s  %s\n' "$k" "$k" "$st" "$boot" \
      "$mods" "${notes% · }"
  done < <(releases)
}

preview() { # release
  local k=$1 p signer
  [[ -n $k ]] || return 0
  printf 'Kernel %s (%s)\n\nPackages:\n' "$k" "$(state "$k")"
  while IFS= read -r p; do
    [[ -n $p ]] && printf '  %-44s %s\n' "$p" "$(pkg_status "$p")"
  done < <(packages_for "$k")

  printf '\n/boot:\n'
  while IFS= read -r p; do
    [[ -n $p ]] && printf '  %6s  %s\n' "$(size_of "$p")" "$p"
  done < <(boot_files "$k")

  printf '\nNVIDIA module: '
  if modinfo -k "$k" nvidia >/dev/null 2>&1; then
    signer=$(modinfo -k "$k" -F signer nvidia 2>/dev/null || true)
    echo "${signer:+signed by }${signer:-unsigned}"
  else
    echo "none"
  fi
  printf '\nDKMS:\n'
  dkms status -k "$k" 2>/dev/null | sed 's/^/  /' || true
}

confirm() { # question -> 0 on y/yes
  local ans
  read -r -p "$1 [y/N] " ans || ans=''
  [[ $ans == [yY] || $ans == [yY][eE][sS] ]]
}

purge() { # release...
  local k running meta p extra
  local -a pkgs=() dirs=() more=() removed=() extras=()
  running=$(uname -r)
  meta=$(meta_target)
  for k; do
    if [[ $k == "$running" ]]; then
      echo "skip $k: it is the running kernel"
      continue
    fi
    if [[ $k == "$meta" ]]; then
      echo "skip $k: $META depends on it (purging it would end kernel" \
        "updates)"
      continue
    fi
    mapfile -t more < <(packages_for "$k")
    pkgs+=("${more[@]}")
    if [[ -d /lib/modules/$k ]]; then dirs+=("$k"); fi
  done
  if ((${#pkgs[@]} == 0 && ${#dirs[@]} == 0)); then
    echo "nothing to purge"
    return 0
  fi

  if ((${#pkgs[@]})); then
    # What apt would really remove, dependants included.
    mapfile -t removed < <(apt-get -s -o Debug::NoLocking=1 purge \
      "${pkgs[@]}" 2>/dev/null | awk '/^(Purg|Remv) / { print $2 }' | sort)
    for p in "${removed[@]}"; do
      [[ " ${pkgs[*]} " == *" $p "* ]] || extras+=("$p")
    done
    echo "apt would purge:"
    printf '  %s\n' "${removed[@]}"
    if ((${#extras[@]})); then
      echo
      echo "WARNING: that includes packages you did not pick:"
      printf '  %s\n' "${extras[@]}"
    fi
  fi
  for k in "${dirs[@]}"; do
    echo "and remove what is left of /lib/modules/$k"
  done
  echo
  confirm "Go ahead?" || {
    echo "cancelled"
    return 0
  }

  if ((${#pkgs[@]})); then
    sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "${pkgs[@]}"
  fi
  for k in "${dirs[@]}"; do
    # Only a folder whose kernel is gone, named like a kernel release.
    [[ $k != "$running" && $k =~ ^[0-9][A-Za-z0-9.+~_-]*$ ]] || continue
    [[ $(pkg_status "linux-image-$k") != ii* ]] || continue
    if [[ -d /lib/modules/$k ]]; then
      sudo rm -rf -- "/lib/modules/$k"
      echo "removed /lib/modules/$k"
    fi
  done
  extra=$(df --output=pcent /boot 2>/dev/null | awk 'NR == 2' | tr -d ' ')
  echo "done; /boot is ${extra:-?} used"
}

main() {
  case ${1:-} in
    --preview)
      preview "${2:-}"
      exit 0
      ;;
    -h | --help) usage ;;
    "") ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  ((EUID != 0)) || die "run as your normal user; it asks for sudo to purge"
  command -v fzf >/dev/null 2>&1 ||
    die "fzf not found (07-dev-toolshed.sh installs it with mise)"

  local out key
  local -a picked
  while true; do
    out=$(list_rows | fzf --multi --layout=reverse --no-sort \
      --delimiter=$'\t' --with-nth=2 --header-lines=1 \
      --header='Tab: select · Ctrl-X: purge · Esc: quit' \
      --preview "'$SELF' --preview {1}" --preview-window=right,45% \
      --bind 'enter:ignore' --expect=ctrl-x) || return 0
    key=$(awk 'NR == 1' <<<"$out")
    mapfile -t picked < <(awk -F'\t' 'NR > 1 && $1 != "" { print $1 }' \
      <<<"$out")
    if [[ $key != ctrl-x || ${#picked[@]} -eq 0 ]]; then continue; fi
    echo
    purge "${picked[@]}"
    echo
    read -r -p "Press Enter to go back to the list " _ || true
  done
}

main "$@"
