#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 11-configure-firefox.sh
#
# Firefox prefs from conf/firefox/user-prefs.js: sites can't override
# browser or extension shortcuts, no GTK emoji picker on Ctrl+., and the
# KDE Plasma global menu.
#
# Usage:
#   ./11-configure-firefox.sh [--dry-run] [--yes]
#
#   Launch Firefox once (to create a profile) and quit it before the first
#   run. Restart Firefox afterwards to apply changes.
#
# Config (symlinked from conf/):
#   ~/.config/ff/user-prefs.js     firefox/user-prefs.js
#   <default profile>/user.js      -> ~/.config/ff/user-prefs.js
#
# Notes:
#   * Firefox itself is installed by 10-apps.sh (Mozilla's .deb).
#   * Firefox reads user.js at startup and copies the values into
#     prefs.js, so removing a line from user-prefs.js does not reset it;
#     reset it in about:config.
#   * Snap Firefox can't read hidden dirs like ~/.config; use Mozilla's
#     .deb.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

PREFS_LINK="${XDG_CONFIG_HOME:-$HOME/.config}/ff/user-prefs.js"

# Needed by the global-menu prefs.
PACKAGES=(
  appmenu-gtk3-module
  libdbusmenu-gtk3-4
  libdbusmenu-glib4
)

PROFILE_ROOTS=(
  "$HOME/.config/mozilla/firefox"
  "$HOME/.mozilla/firefox"
  "$HOME/snap/firefox/common/.mozilla/firefox"
)

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

# The profile the installed Firefox opens by default.
AWK_INSTALL_DEFAULT='
  /^\[Install/ { f = 1; next }
  /^\[/ { f = 0 }
  f && $1 == "Default" { print $2; exit }'

# Fallback: the profile marked Default=1.
AWK_PROFILE_DEFAULT='
  /^\[Profile/ { path = "" }
  $1 == "Path" { path = $2 }
  $1 == "Default" && $2 == 1 { print path; exit }'

# Fallback: the only profile listed.
AWK_FIRST_PROFILE='$1 == "Path" { print $2; exit }'

# Print the absolute path of the default Firefox profile.
find_profile() {
  local base ini p prog
  for base in "${PROFILE_ROOTS[@]}"; do
    ini="$base/profiles.ini"
    [[ -f $ini ]] || continue
    p=''
    for prog in "$AWK_INSTALL_DEFAULT" "$AWK_PROFILE_DEFAULT" \
      "$AWK_FIRST_PROFILE"; do
      p=$(awk -F= "$prog" "$ini")
      [[ -z $p ]] || break
    done
    [[ -n $p ]] || continue
    [[ $p == /* ]] || p="$base/$p"
    [[ -d $p ]] || continue
    printf '%s\n' "$p"
    return 0
  done
  return 1
}

firefox_running() {
  pgrep -x firefox >/dev/null || pgrep -x firefox-bin >/dev/null
}

install_packages() {
  step "Packages"
  apt_ensure "${PACKAGES[@]}"
}

link_prefs() {
  step "Prefs"
  local profile
  profile=$(find_profile) ||
    die "no Firefox profile found; launch Firefox once, quit it," \
      "then re-run"
  info "profile: $(pretty "$profile")"
  if [[ $profile == "$HOME/snap/"* ]]; then
    warn "snap Firefox: its sandbox can't read ~/.config, so user.js" \
      "may not load; use Mozilla's .deb"
  fi

  LINK_CHANGED=0
  link_conf firefox/user-prefs.js "$PREFS_LINK"
  ensure_link "$PREFS_LINK" "$profile/user.js"

  ((LINK_CHANGED && !DRY_RUN)) || return 0
  if firefox_running; then
    info "Firefox is running; restart it to apply the prefs"
  else
    info "prefs apply on the next Firefox launch"
  fi
}

main() {
  lib_init "Firefox prefs (user.js)" "$@"
  no_extra_args
  require_user
  need_sudo

  install_packages
  link_prefs
}

main "$@"
