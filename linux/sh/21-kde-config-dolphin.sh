#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 21-kde-config-dolphin.sh
#
# Dolphin: show hidden files (dotfiles) in every folder by default, and
# smaller icons/rows in all three view modes so listings are more compact.
#
# Usage:
#   ./21-kde-config-dolphin.sh [--dry-run] [--yes]
#
#   Tweak the Settings block below, then re-run.
#
# Notes:
#   * "Show hidden files" is a per-folder view property. It only sticks
#     everywhere once Dolphin shares one set of view properties for all
#     folders (dolphinrc [General] GlobalViewProps=true).
#   * Dolphin >= 24.05 keeps view properties in an extended attribute
#     (user.kde.fm.viewproperties#1) on
#     ~/.local/share/dolphin/view_properties/global, not in a .directory
#     file; this falls back to .directory without xattr support.
#   * Dolphin rewrites its config on exit, so it must be closed while this
#     writes. It is only closed (after asking) when something would
#     change.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# Show files and folders starting with "." in every folder.
SHOW_HIDDEN=true

# Default view mode for all folders: icons | compact | details | ""
# (leave as-is).
VIEW_MODE=""

# Icon sizes in px. Dolphin's zoom steps are 16, 22, 32, 48, 64, 80, 96.
# PreviewSize is used instead of IconSize when previews are on, so keep
# them equal or previews make rows big again. "" = leave as-is.
DETAILS_ICON_SIZE=16 # Details (list with columns). Dolphin default: 22
DETAILS_PREVIEW_SIZE=16
COMPACT_ICON_SIZE=16 # Compact (columns of icons + names). Default: 22
COMPACT_PREVIEW_SIZE=16
ICONS_ICON_SIZE=48 # Icons (grid). Default: 64
ICONS_PREVIEW_SIZE=48

# Icons view: label width (0 = small, 1 = medium, 2 = large) and the
# maximum number of lines a file name may wrap to (0 = unlimited).
# Defaults: 1 and 3.
ICONS_TEXT_WIDTH=0
ICONS_MAX_TEXT_LINES=2

# Places sidebar icon size in px ("" = leave as-is, -1 = automatic).
PLACES_ICON_SIZE=16

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

GLOBAL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
GLOBAL_DIR+="/dolphin/view_properties/global"
VIEW_MODE_NUM=""
VIEW_DIFFS=0

# group|key|value
RC_KEYS=()

build_wanted() {
  case $VIEW_MODE in
    icons) VIEW_MODE_NUM=0 ;;
    details) VIEW_MODE_NUM=1 ;;
    compact) VIEW_MODE_NUM=2 ;;
    "") VIEW_MODE_NUM="" ;;
    *)
      die "VIEW_MODE must be icons, compact, details or empty" \
        "(got '$VIEW_MODE')"
      ;;
  esac
  RC_KEYS=(
    "General|GlobalViewProps|true"
    "DetailsMode|IconSize|$DETAILS_ICON_SIZE"
    "DetailsMode|PreviewSize|$DETAILS_PREVIEW_SIZE"
    "CompactMode|IconSize|$COMPACT_ICON_SIZE"
    "CompactMode|PreviewSize|$COMPACT_PREVIEW_SIZE"
    "IconsMode|IconSize|$ICONS_ICON_SIZE"
    "IconsMode|PreviewSize|$ICONS_PREVIEW_SIZE"
    "IconsMode|TextWidthIndex|$ICONS_TEXT_WIDTH"
    "IconsMode|MaximumTextLines|$ICONS_MAX_TEXT_LINES"
    "PlacesPanel|IconSize|$PLACES_ICON_SIZE"
  )
}

# Global view properties, through Python's configparser.
#   check: print "same|diff <TAB> [Section] Key <TAB> have <TAB> want"
#   apply: write the changes
view_props() { # check|apply
  python3 -I - "$1" "$GLOBAL_DIR" "$SHOW_HIDDEN" "$VIEW_MODE_NUM" <<'PY'
import configparser, datetime, errno, io, os, sys

mode, d, show_hidden, view_mode = sys.argv[1:5]
attr = "user.kde.fm.viewproperties#1"
legacy = os.path.join(d, ".directory")
nosup = (errno.ENOTSUP, getattr(errno, "EOPNOTSUPP", errno.ENOTSUP))

text, use_xattr = "", True
try:
    if os.path.isdir(d):
        text = os.getxattr(d, attr).decode()
except OSError as e:
    if e.errno in nosup:
        use_xattr = False
if not text and os.path.isfile(legacy):
    text = open(legacy).read()

cp = configparser.ConfigParser(interpolation=None, strict=False)
cp.optionxform = str  # keep KConfig key case
cp.read_string(text)
for s in ("Dolphin", "Settings"):
    if not cp.has_section(s):
        cp.add_section(s)
cp["Dolphin"].setdefault("Version", "4")

wanted = [("Settings", "HiddenFilesShown", show_hidden)]
if view_mode:
    wanted.append(("Dolphin", "ViewMode", view_mode))

changed = False
for sec, key, val in wanted:
    have = cp[sec].get(key)
    if mode == "check":
        state = "same" if have == val else "diff"
        print(state, f"[{sec}] {key}", have or "(unset)", val, sep="\t")
    if have != val:
        changed = True
        cp[sec][key] = val

if mode == "apply" and changed:
    os.makedirs(d, exist_ok=True)
    n = datetime.datetime.now()
    cp["Dolphin"]["Timestamp"] = (
        f"{n.year},{n.month},{n.day},{n.hour},{n.minute},"
        f"{n.second}.{n.microsecond // 1000:03d}"
    )
    buf = io.StringIO()
    cp.write(buf, space_around_delimiters=False)
    out = buf.getvalue().rstrip("\n") + "\n"
    if use_xattr:
        os.setxattr(d, attr, out.encode())
    else:
        with open(legacy, "w") as f:
            f.write(out)
PY
}

# True if anything would change.
plan_changes() {
  local entry group key want cur pending=0
  for entry in "${RC_KEYS[@]}"; do
    IFS='|' read -r group key want <<<"$entry"
    [[ -n $want ]] || continue
    cur=$(kreadconfig6 --file dolphinrc --group "$group" --key "$key")
    [[ $cur == "$want" ]] || pending=1
  done
  local state
  while IFS=$'\t' read -r state _; do
    if [[ $state == diff ]]; then
      VIEW_DIFFS=1
      pending=1
    fi
  done < <(view_props check)
  return $((!pending))
}

_close_dolphin() {
  # SIGTERM skips Dolphin's save-on-exit, which is what we want here.
  pkill -TERM -x dolphin || true
  local _
  for _ in $(seq 50); do
    pgrep -x dolphin >/dev/null || return 0
    sleep 0.1
  done
  echo "Dolphin did not exit"
  return 1
}

close_dolphin() {
  step "Dolphin"
  if ! pgrep -x dolphin >/dev/null; then
    skip "Dolphin is not running"
    return 0
  fi
  local q="Dolphin is running and would overwrite these settings on exit."
  confirm "$q Close it now?" || die "close Dolphin and re-run"
  apply "close Dolphin" _close_dolphin
}

configure_dolphinrc() {
  step "dolphinrc"
  local entry group key want
  for entry in "${RC_KEYS[@]}"; do
    IFS='|' read -r group key want <<<"$entry"
    [[ -n $want ]] || continue
    kconf_set dolphinrc "$group" "$key" "$want"
  done
}

configure_view_props() {
  step "Global view properties"
  local state key cur want
  while IFS=$'\t' read -r state key cur want; do
    if [[ $state == same ]]; then
      skip "$key = $want"
    else
      info "$key: $cur → $want"
    fi
  done < <(view_props check)
  if ((VIEW_DIFFS)); then
    apply "write global view properties ($(pretty "$GLOBAL_DIR"))" \
      view_props apply
  fi
}

main() {
  lib_init "Dolphin: hidden files, compact views" "$@"
  no_extra_args
  require_user
  require_plasma
  require_cmd kreadconfig6 kwriteconfig6 python3

  build_wanted
  if plan_changes; then
    close_dolphin
  fi
  configure_dolphinrc
  configure_view_props
  if ((_N_CHANGED && !DRY_RUN)); then
    info "start Dolphin to see the changes;" \
      "Ctrl+H still toggles hidden files"
  fi
}

main "$@"
