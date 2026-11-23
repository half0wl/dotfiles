#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 00-set-default-dirs.sh
#
# Fewer folders in ~: point the XDG user dirs at ~/Documents (music,
# pictures, videos) or hidden folders (templates, public share), then remove
# the default folders that go unused (~/Music, ~/Videos, ...), and make
# sure ~/Desktop, ~/Documents, ~/Downloads and ~/Workspace exist. An
# empty folder is removed straight away; a folder with something in it is
# listed and only removed after you confirm.
#
# Usage:
#   ./00-set-default-dirs.sh [--dry-run] [--yes]
#
#   --yes also removes folders that are not empty, without asking.
#   Log out and back in afterwards: running apps keep the old locations.
#
# Config (symlinked from conf/):
#   ~/.config/user-dirs.dirs   xdg/user-dirs.dirs (where each XDG dir goes)
#   ~/.config/user-dirs.conf   xdg/user-dirs.conf (enabled=False, so
#                              xdg-user-dirs-update never rewrites them)
#
# Notes:
#   * Linked first, so nothing points at a folder after it is removed.
#   * ~/Desktop is kept on purpose: Plasma's Folder View desktop shows
#     XDG_DESKTOP_DIR, so without it the desktop shows your whole home
#     folder.
#   * Dolphin's Places panel keeps entries for removed folders; remove
#     those by hand.
#   * Symlinks are never followed: a folder that is a symlink is skipped.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# Folders under $HOME to create. The first five are what the XDG dirs
# point at, with the two hidden ones for templates and public share; with
# xdg-user-dirs-update disabled, nothing else creates them on a fresh
# install.
CREATE=(
  Desktop
  Documents
  Downloads
  .local/share/templates
  .local/share/public
  Workspace
)

# Folders under $HOME to remove (not Desktop: see Notes).
DIRS=(
  Music
  Pictures
  Public
  Templates
  Videos
)

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

# Print up to 10 entries of DIR (top two levels), indented.
show_contents() { # dir
  local entries entry
  # awk, not head: head exits early, sort then dies of SIGPIPE, and
  # pipefail would fail the script. || true: an unreadable subfolder
  # makes find fail, which shouldn't stop the listing either.
  entries=$(find "$1" -mindepth 1 -maxdepth 2 2>/dev/null | sort |
    awk 'NR <= 10' || true)
  while IFS= read -r entry; do
    if [[ -n $entry ]]; then detail "$(pretty "$entry")"; fi
  done <<<"$entries"
}

remove_dir() { # name
  local name=$1 dir="$HOME/$1" count
  if [[ -L $dir ]]; then
    warn "$(pretty "$dir") is a symlink; skipping it"
    return 0
  fi
  if [[ ! -e $dir ]]; then
    skip "$(pretty "$dir") already gone"
    return 0
  fi
  if [[ ! -d $dir ]]; then
    warn "$(pretty "$dir") is not a folder; skipping it"
    return 0
  fi

  # || true: find fails on an unreadable subfolder; wc's count still
  # stands (and any count above 0 means "ask first").
  count=$(find "$dir" -mindepth 1 2>/dev/null | wc -l || true)
  if ((count == 0)); then
    apply "remove empty $(pretty "$dir")" rmdir -- "$dir"
    return 0
  fi

  warn "$(pretty "$dir") is not empty ($count entries):"
  show_contents "$dir"
  if confirm "Delete $(pretty "$dir") and everything in it?"; then
    apply "remove $(pretty "$dir") ($count entries)" rm -rf -- "$dir"
  else
    info "kept $(pretty "$dir")"
  fi
}

link_xdg_config() {
  step "XDG user dirs"
  link_conf xdg/user-dirs.conf "$HOME/.config/user-dirs.conf"
  link_conf xdg/user-dirs.dirs "$HOME/.config/user-dirs.dirs"
}

create_dirs() {
  step "Folders to create"
  local name dir
  for name in "${CREATE[@]}"; do
    dir="$HOME/$name"
    if [[ -d $dir ]]; then
      skip "$(pretty "$dir") exists"
    elif [[ -e $dir || -L $dir ]]; then
      warn "$(pretty "$dir") exists but is not a folder; skipping it"
    else
      apply "create $(pretty "$dir")" mkdir -p -- "$dir"
    fi
  done
}

remove_dirs() {
  step "Default folders"
  [[ -n ${HOME:-} && $HOME == /* && $HOME != / ]] ||
    die "HOME is not a usable path: '${HOME:-}'"
  local name
  for name in "${DIRS[@]}"; do
    [[ -n $name && $name != */* && $name != . && $name != .. ]] ||
      die "bad folder name in DIRS: '$name'"
    remove_dir "$name"
  done
}

main() {
  lib_init "XDG dirs to ~/Documents, remove unused home folders" "$@"
  no_extra_args
  require_user

  link_xdg_config
  create_dirs
  remove_dirs
}

main "$@"
