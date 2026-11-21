#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 22-kde-config-spaces.sh
#
# macOS Mission Control + Spaces on Plasma: Meta+Up opens the Overview
# (browse, create, rename and drag windows between virtual desktops),
# Meta+Left / Meta+Right switch to the previous / next desktop, Alt+Tab
# shows windows from every desktop, and desktops sit in a single row.
#
# Usage:
#   ./22-kde-config-spaces.sh [--dry-run] [--yes]
#
#   Run inside Plasma. Tweak the Settings block below, then re-run.
#
# Notes:
#   * keyd maps the physical Ctrl+Up/Left/Right to Meta+Up/Left/Right (see
#     conf/keyd/default.conf), so the macOS keys work too.
#   * Shortcuts are set over D-Bus (kglobal_set in _lib.sh explains why).
#   * Desktops are never created, renamed or removed: add them in the
#     Overview (+ on the desktop strip).
#   * Per-screen virtual desktops need Plasma >= 6.7; Debian 13 ships 6.3,
#     so all monitors share one set of desktops.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# What opens the Overview. "none" leaves the action unbound.
OVERVIEW_KEYS="Meta+Up"

# Where "Window Quick Tile Top" goes. "none" simply frees Meta+Up; ""
# leaves the action exactly as it is.
TILE_TOP_KEYS="Meta+Shift+Up"

# Previous / next desktop (macOS: Ctrl+Left / Ctrl+Right between Spaces).
SWITCH_LEFT_KEYS="Meta+Left"
SWITCH_RIGHT_KEYS="Meta+Right"

# Where "Window Quick Tile Left/Right" go once Meta+Left/Right are taken
# ("" = leave as-is, but then the switch keys above clash and won't
# stick).
TILE_LEFT_KEYS="Meta+Ctrl+Left"
TILE_RIGHT_KEYS="Meta+Ctrl+Right"

# Wrap from the last desktop back to the first? macOS stops at the ends.
WRAP_AROUND=false

# Alt+Tab lists windows from every desktop (true) or only the current one
# (false, the KWin default). Picking a window elsewhere switches there.
ALT_TAB_ALL_DESKTOPS=true

# Rows in the desktop grid. Keep 1 for macOS-style left/right navigation.
DESKTOP_ROWS=1

# ---------------------------------------------------------------------------
# KWin D-Bus helpers
# ---------------------------------------------------------------------------

VDM=(org.kde.KWin /VirtualDesktopManager)

gdbus_call() {
  local dest=$1 path=$2 method=$3
  shift 3
  gdbus call --session --dest "$dest" --object-path "$path" \
    --method "$method" "$@"
}

vdesk_prop() {
  gdbus_call "${VDM[@]}" org.freedesktop.DBus.Properties.Get \
    org.kde.KWin.VirtualDesktopManager "$1" |
    sed -E 's/.*uint32 ([0-9]+).*/\1/'
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

check_session() {
  require_cmd gdbus kreadconfig6 kwriteconfig6
  gdbus introspect --session --dest org.kde.KWin --object-path /KWin \
    >/dev/null 2>&1 || die "cannot reach org.kde.KWin on the session bus"
  gdbus introspect --session --dest org.kde.kglobalaccel \
    --object-path /kglobalaccel >/dev/null 2>&1 ||
    die "cannot reach org.kde.kglobalaccel on the session bus"
  local ver
  ver=$(plasmashell --version 2>/dev/null | awk '{print $2}')
  info "Plasma $ver (${XDG_SESSION_TYPE:-?} session)"
}

configure_shortcuts() {
  step "Shortcuts"
  local overview_id tile_id
  overview_id=$(kglobal_id kwin "Overview")
  tile_id=$(kglobal_id kwin "Window Quick Tile Top")

  # Free Meta+Up first: kglobalaccel silently drops clashing keys.
  if [[ -n $TILE_TOP_KEYS ]]; then
    kglobal_set "$tile_id" "$TILE_TOP_KEYS" "Quick Tile Top"
  else
    skip "Quick Tile Top left as-is"
  fi
  kglobal_set "$overview_id" "$OVERVIEW_KEYS" "Overview (Spaces)"

  swap_with_tile Left "$SWITCH_LEFT_KEYS" "$TILE_LEFT_KEYS"
  swap_with_tile Right "$SWITCH_RIGHT_KEYS" "$TILE_RIGHT_KEYS"
}

# Desktop switch and quick tile trade keys: a cycle (each wants the
# other's key), so park the tile action on nothing, give the switch
# action its key, then put the tile action on the freed one.
swap_with_tile() { # Left|Right switch-keys tile-keys
  local dir=$1 switch_keys=$2 tile_keys=$3 switch_id tile_id
  switch_id=$(kglobal_id kwin "Switch One Desktop to the ${dir}")
  tile_id=$(kglobal_id kwin "Window Quick Tile ${dir}")
  if [[ -n $tile_keys &&
    $(kglobal_keys "$tile_id") != "$(qkey "$tile_keys")" ]]; then
    kglobal_set "$tile_id" none "Quick Tile ${dir} (parked)"
  fi
  kglobal_set "$switch_id" "$switch_keys" "Switch Desktop ${dir}"
  if [[ -n $tile_keys ]]; then
    kglobal_set "$tile_id" "$tile_keys" "Quick Tile ${dir}"
  fi
}

configure_kwin() {
  step "KWin"
  kconf_set --default true kwinrc Effect-overview Enabled true
  kconf_set --default true kwinrc Windows RollOverDesktops "$WRAP_AROUND"
  # [TabBox] DesktopMode: 0 = all desktops, 1 = current only (default).
  local mode=1
  [[ $ALT_TAB_ALL_DESKTOPS == true ]] && mode=0
  kconf_set --default 1 kwinrc TabBox DesktopMode "$mode"
}

configure_desktops() {
  step "Virtual desktops"
  local count rows
  count=$(vdesk_prop count)
  if ((count < 2 || DESKTOP_ROWS < 1)); then
    skip "$count desktop(s); no grid to arrange"
    return 0
  fi
  rows=$((DESKTOP_ROWS > count ? count : DESKTOP_ROWS))
  if [[ $(vdesk_prop rows) == "$rows" ]]; then
    skip "desktop grid: $rows row(s)"
  else
    apply "desktop grid: $rows row(s)" \
      gdbus_call "${VDM[@]}" org.freedesktop.DBus.Properties.Set \
      org.kde.KWin.VirtualDesktopManager rows "<uint32 $rows>"
  fi
}

reload_kwin() {
  if ((KCONF_CHANGED)); then
    apply "reload KWin config" \
      gdbus_call org.kde.KWin /KWin org.kde.KWin.reconfigure
  fi
  ((KGLOBAL_PROBLEMS == 0)) ||
    die "$KGLOBAL_PROBLEMS shortcut(s) did not verify"
}

usage_tips() {
  ((_N_CHANGED && !DRY_RUN)) || return 0
  step "Using it"
  info "$OVERVIEW_KEYS opens Overview (Spaces): + on the strip adds a" \
    "desktop, drag a window onto a thumbnail to move it, right-click to" \
    "rename/remove"
  info "$SWITCH_LEFT_KEYS / $SWITCH_RIGHT_KEYS: previous / next desktop"
  info "moved to make room: $TILE_LEFT_KEYS / $TILE_RIGHT_KEYS /" \
    "$TILE_TOP_KEYS = quick tile left / right / top"
  info "also useful: Meta+G = Grid View, a Mission-Control-style grid"
}

main() {
  lib_init "Mission Control + Spaces on Plasma" "$@"
  no_extra_args
  require_user
  require_plasma

  check_session
  configure_shortcuts
  configure_kwin
  configure_desktops
  reload_kwin
  usage_tips
}

main "$@"
