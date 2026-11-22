#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 25-kde-config-spectacle.sh
#
# Spectacle: where screenshots and screen recordings are saved, and how
# they are named. Creates the folders if they are missing.
#
# Usage:
#   ./25-kde-config-spectacle.sh [--dry-run] [--yes]
#
#   Tweak the Settings block below, then re-run.
#
# Config:
#   spectaclerc [ImageSave] / [VideoSave] (Settings below)
#
# Notes:
#   * Spectacle stores folders as file:// URLs with a trailing slash; this
#     writes them the same way.
#   * Spectacle reads its config at start and may write it back on exit,
#     so it must be closed while this writes. It is only closed (after
#     asking) when something would change.
#   * Filename placeholders (<yyyy>, <MM>, <HH>, ...): Spectacle's
#     Configure dialog lists them all.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

IMAGE_DIR="$HOME/Documents/screencaps/images"
VIDEO_DIR="$HOME/Documents/screencaps/videos"

IMAGE_FILENAME="c_<yyyy><MM><dd>_<HH><mm><ss>"
VIDEO_FILENAME="c_<yyyy><MM><dd>_<HH><mm><ss>"

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

# group|key|value
RC_KEYS=()

build_wanted() {
  RC_KEYS=(
    "ImageSave|imageSaveLocation|file://$IMAGE_DIR/"
    "ImageSave|imageFilenameTemplate|$IMAGE_FILENAME"
    "VideoSave|videoSaveLocation|file://$VIDEO_DIR/"
    "VideoSave|videoFilenameTemplate|$VIDEO_FILENAME"
  )
}

# True if any key would change.
plan_changes() {
  local entry group key want cur
  for entry in "${RC_KEYS[@]}"; do
    IFS='|' read -r group key want <<<"$entry"
    cur=$(kreadconfig6 --file spectaclerc --group "$group" --key "$key")
    [[ $cur == "$want" ]] || return 0
  done
  return 1
}

_close_spectacle() {
  pkill -TERM -x spectacle || true
  local _
  for _ in $(seq 50); do
    pgrep -x spectacle >/dev/null || return 0
    sleep 0.1
  done
  echo "Spectacle did not exit"
  return 1
}

close_spectacle() {
  step "Spectacle"
  if ! pgrep -x spectacle >/dev/null; then
    skip "Spectacle is not running"
    return 0
  fi
  local q="Spectacle is running and may overwrite these settings on exit."
  confirm "$q Close it now?" || die "close Spectacle and re-run"
  apply "close Spectacle" _close_spectacle
}

create_dirs() {
  step "Folders"
  local d
  for d in "$IMAGE_DIR" "$VIDEO_DIR"; do
    if [[ -d $d ]]; then
      skip "$(pretty "$d") exists"
    else
      apply "create $(pretty "$d")" mkdir -p -- "$d"
    fi
  done
}

configure_spectaclerc() {
  step "spectaclerc"
  local entry group key want
  for entry in "${RC_KEYS[@]}"; do
    IFS='|' read -r group key want <<<"$entry"
    kconf_set spectaclerc "$group" "$key" "$want"
  done
}

main() {
  lib_init "Spectacle: save folders and file names" "$@"
  no_extra_args
  require_user
  require_plasma
  require_cmd kreadconfig6 kwriteconfig6

  build_wanted
  if plan_changes; then
    close_spectacle
  fi
  create_dirs
  configure_spectaclerc
}

main "$@"
