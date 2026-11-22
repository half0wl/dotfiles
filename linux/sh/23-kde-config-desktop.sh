#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 23-kde-config-desktop.sh
#
# The rest of the Plasma desktop: animation speed, key repeat, mice,
# screen locking, session restore, Night Color, the monitor mode/scale,
# and app launch shortcuts that should stay unbound.
#
# Usage:
#   ./23-kde-config-desktop.sh [--dry-run] [--yes]
#
#   Run inside Plasma. Tweak the Settings block below, then re-run. Log
#   out and back in afterwards for keyboard, mouse and session settings.
#
# Notes:
#   * Themes and panel layouts are not managed; set them in System
#     Settings.
#   * Caps Lock -> Esc is done by keyd (06-keyd.sh), not here.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# Animation duration factor: 1 = default, lower = faster, 0 = off.
ANIMATION_FACTOR=0.35355339059327373

# Key repeat: delay before repeating (ms) and repeats per second.
KEY_REPEAT_DELAY=150
KEY_REPEAT_RATE=10

# Lock the screen automatically after idling, and after how many minutes
# (0 = never).
SCREEN_AUTOLOCK=false
SCREEN_LOCK_TIMEOUT=0

# On login: emptySession | restorePreviousLogout | restoreSavedSession
SESSION_RESTORE=emptySession

NIGHT_COLOR=true

# Mice, by libinput group: Libinput/<vendor id>/<product id>/<name>.
MX="Libinput/1133/45108/Logitech MX Master 3S"
RIVAL="Libinput/4152/5920/SteelSeries SteelSeries Rival 310 eSports Mouse"
# group|key|value
MOUSE_SETTINGS=(
  "$MX|NaturalScroll|true"
  "$RIVAL|NaturalScroll|true"
  "$RIVAL|PointerAcceleration|-0.600"
  "$RIVAL|ScrollMethod|4"
)

# Monitor ("" output = leave displays alone). VRR: never|always|automatic
DISPLAY_OUTPUT=DP-4
DISPLAY_MODE=3440x1440@144
DISPLAY_SCALE=1.15
DISPLAY_VRR=never

# Apps whose global launch shortcut should stay unbound (.desktop ids).
UNBOUND_LAUNCHERS=(
  com.mitchellh.ghostty.desktop
  org.kde.plasma.emojier.desktop
)

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

configure_animations() {
  step "Animations"
  kconf_set --notify --default 1 kdeglobals KDE AnimationDurationFactor \
    "$ANIMATION_FACTOR"
}

configure_input() {
  step "Keyboard and mice"
  kconf_set kcminputrc Keyboard RepeatDelay "$KEY_REPEAT_DELAY"
  kconf_set kcminputrc Keyboard RepeatRate "$KEY_REPEAT_RATE"
  local entry group key value
  for entry in "${MOUSE_SETTINGS[@]}"; do
    IFS='|' read -r group key value <<<"$entry"
    kconf_set kcminputrc "$group" "$key" "$value"
  done
}

configure_session() {
  step "Session"
  kconf_set --default true kscreenlockerrc Daemon Autolock \
    "$SCREEN_AUTOLOCK"
  kconf_set --default 5 kscreenlockerrc Daemon Timeout \
    "$SCREEN_LOCK_TIMEOUT"
  kconf_set --default restorePreviousLogout ksmserverrc General \
    loginMode "$SESSION_RESTORE"
  kconf_set --default false kwinrc NightColor Active "$NIGHT_COLOR"
}

# Print "<WxH@Hz> <scale> <vrr>" for an output, from KWin's own config.
current_display() { # output
  python3 -I - "$1" "$HOME/.config/kwinoutputconfig.json" <<'PY'
import json, sys
name, path = sys.argv[1:3]
for block in json.load(open(path)):
    if block.get("name") != "outputs":
        continue
    for o in block.get("data", []):
        if o.get("connectorName") != name:
            continue
        m = o.get("mode", {})
        hz = round(m.get("refreshRate", 0) / 1000)
        print(f"{m.get('width')}x{m.get('height')}@{hz}",
              o.get("scale"), str(o.get("vrrPolicy", "")).lower())
        sys.exit(0)
PY
}

configure_display() {
  step "Display"
  if [[ -z $DISPLAY_OUTPUT ]]; then
    skip "displays left as-is"
    return 0
  fi
  local connected
  connected=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
  if ! grep -qE "Output: [0-9]+ $DISPLAY_OUTPUT( |$)" <<<"$connected"; then
    skip "$DISPLAY_OUTPUT is not connected"
    return 0
  fi

  local mode scale vrr out="output.$DISPLAY_OUTPUT"
  read -r mode scale vrr <<<"$(current_display "$DISPLAY_OUTPUT")"
  if [[ $mode == "$DISPLAY_MODE" ]]; then
    skip "$DISPLAY_OUTPUT mode = $DISPLAY_MODE"
  else
    apply "$DISPLAY_OUTPUT mode: ${mode:-?} → $DISPLAY_MODE" \
      kscreen-doctor "$out.mode.$DISPLAY_MODE"
  fi
  if [[ $scale == "$DISPLAY_SCALE" ]]; then
    skip "$DISPLAY_OUTPUT scale = $DISPLAY_SCALE"
  else
    apply "$DISPLAY_OUTPUT scale: ${scale:-?} → $DISPLAY_SCALE" \
      kscreen-doctor "$out.scale.$DISPLAY_SCALE"
  fi
  if [[ $vrr == "$DISPLAY_VRR" ]]; then
    skip "$DISPLAY_OUTPUT VRR = $DISPLAY_VRR"
  else
    apply "$DISPLAY_OUTPUT VRR: ${vrr:-?} → $DISPLAY_VRR" \
      kscreen-doctor "$out.vrrpolicy.$DISPLAY_VRR"
  fi
  # Legacy X11 apps get the same scale.
  kconf_set kwinrc Xwayland Scale "$DISPLAY_SCALE"
}

configure_shortcuts() {
  step "Launch shortcuts"
  local app actions
  for app in "${UNBOUND_LAUNCHERS[@]}"; do
    actions=$(_kga allActionsForComponent "['$app']" 2>/dev/null || true)
    if [[ $actions != *"'_launch'"* ]]; then
      skip "$app has no launch shortcut registered"
      continue
    fi
    kglobal_set "$(kglobal_id "$app" _launch)" none "launch $app"
  done
}

finish() {
  if ((KCONF_CHANGED)); then
    apply "reload KWin config" gdbus call --session --dest org.kde.KWin \
      --object-path /KWin --method org.kde.KWin.reconfigure
  fi
  ((KGLOBAL_PROBLEMS == 0)) ||
    die "$KGLOBAL_PROBLEMS shortcut(s) did not verify"
  if ((KCONF_CHANGED && !DRY_RUN)); then
    step "Next"
    info "log out and back in so keyboard, mouse and session settings" \
      "take effect"
  fi
  return 0
}

main() {
  lib_init "Plasma animations, input, session, display, shortcuts" \
    "$@"
  no_extra_args
  require_user
  require_plasma
  require_cmd kreadconfig6 kwriteconfig6 kscreen-doctor gdbus python3

  configure_animations
  configure_input
  configure_session
  configure_display
  configure_shortcuts
  finish
}

main "$@"
