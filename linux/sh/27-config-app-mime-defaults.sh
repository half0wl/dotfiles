#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 27-config-app-mime-defaults.sh
#
# Sets default apps to open files with. An app that is not installed
# gets a warning and its file types are left alone. The full mapping is
# under File types below.
#
# Usage:
#   ./27-config-app-mime-defaults.sh [--dry-run] [--yes]
#
#   Edit the Settings block below, then re-run.
#
# Config:
#   ~/.local/share/applications/nvim-ghostty.desktop
#                                 applications/nvim-ghostty.desktop
#   ~/.config/mimeapps.list       written with `gio mime` (Settings below)
#
# Notes:
#   * Neovim gets every text/* type in the MIME database (except
#     TEXT_EXCLUDE) plus CODE_TYPES. Okular gets the image/* types its
#     image viewer's .desktop file declares; VLC the video/* and audio/*
#     types its own declares, plus VLC_EXTRA_TYPES. Types that a
#     shared-mime-info or app upgrade adds are picked up on the next run.
#   * The launcher runs nvim through `mise exec`: the Plasma session's
#     PATH has no mise tools, and this way nvim also finds node, rg, ...
#     as it does in a shell.
#   * `gio mime` writes [Default Applications] and [Added Associations];
#     Dolphin and GTK apps both read them.
#   * Re-running resets any of these types changed by hand in "Open With".
#   * Executable AppImages and scripts may be run (or Dolphin asks)
#     instead of opened in the default app.
#   * .mts is typed as MPEG transport stream video, so TypeScript .mts
#     files open in VLC. .ts is typed as a Qt Linguist file, which is
#     text, so it opens in Neovim.
#
# File types:
#   AppImages        Gear Lever
#   Plain text       Neovim (in a Ghostty window)
#   Markdown         Neovim (in a Ghostty window)
#   Shell scripts    Neovim (in a Ghostty window)
#   Source code      Neovim (in a Ghostty window)
#   Images           Okular
#   Video            VLC
#   Audio            VLC

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

GEARLEVER_DESKTOP=it.mijorus.gearlever.desktop
NVIM_DESKTOP=nvim-ghostty.desktop
OKULAR_DESKTOP=okularApplication_kimgio.desktop # Okular's image viewer
VLC_DESKTOP=vlc.desktop

APPIMAGE_TYPES=(
  application/vnd.appimage
)

# Code and config outside text/*. Every text/* type (text/plain,
# text/markdown, text/javascript, text/rust, ...) is included already.
CODE_TYPES=(
  # shell and other scripting languages
  application/x-shellscript application/x-csh application/x-fishscript
  application/x-powershell application/x-bat application/x-perl
  application/x-php application/x-ruby application/x-awk application/x-m4
  application/ecmascript application/vnd.coffeescript
  application/vnd.dart application/x-gdscript application/x-godot-shader
  application/x-asp application/sql
  # .tsx (the MIME database calls it a Tiled tileset)
  application/x-tiled-tsx
  # data and config
  application/json application/json5 application/ld+json
  application/schema+json application/geo+json application/x-ipynb+json
  application/yaml application/toml
  application/xml application/xml-dtd application/xsd application/xslt+xml
)

# text/* types other apps keep.
TEXT_EXCLUDE=(
  text/html text/htmlh                                 # browser
  text/csv text/tab-separated-values text/spreadsheet # spreadsheet
  text/calendar text/vcard                             # calendar, contacts
)

# Types VLC plays that its .desktop file doesn't declare (it lists
# audio/opus, which the MIME database calls audio/x-opus+ogg).
VLC_EXTRA_TYPES=(
  audio/x-opus+ogg audio/x-flac+ogg audio/x-speex+ogg # Ogg-wrapped
  audio/x-m4b                                          # audiobooks
)

MIME_DIR=/usr/share/mime
MIMEAPPS="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
KDE_MIMEAPPS="${XDG_CONFIG_HOME:-$HOME/.config}/kde-mimeapps.list"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
MISE_BIN="$HOME/.local/bin/mise"

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

declare -A KNOWN=()   # every type in the MIME database
declare -A ALIAS=()   # alias -> canonical type
declare -A CURRENT=() # type -> default desktop id, from mimeapps.list
DEFAULTS_CHANGED=0

# text/plain and everything below it in the MIME database's subclass
# list ("child parent" per line), limited to text/*. A few text/* types
# (text/x-devicetree-binary, ...) are binary and not below text/plain.
AWK_TEXT_TYPES='
  { kids[$2] = kids[$2] " " $1 }
  END {
    n = 1; queue[1] = "text/plain"; seen["text/plain"] = 1
    for (i = 1; i <= n; i++) {
      split(kids[queue[i]], k, " ")
      for (j in k) {
        if (k[j] in seen) continue
        seen[k[j]] = 1
        queue[++n] = k[j]
      }
    }
    for (t in seen) if (t ~ /^text\//) print t
  }'

# The types in a .desktop file's MimeType= line that start with one of
# the space-separated prefixes (image/, video/, ...).
AWK_DECLARED_TYPES='
  $1 == "MimeType" {
    n = split($2, t, ";")
    m = split(prefixes, p, " ")
    for (i = 1; i <= n; i++)
      for (j = 1; j <= m; j++)
        if (index(t[i], p[j]) == 1) print t[i]
  }'

# The [Default Applications] lines of mimeapps.list.
AWK_DEFAULTS='
  /^\[/ { f = ($0 == "[Default Applications]"); next }
  f && /=/'

# Run mise from / so no project-local mise.toml is picked up.
mise_at_root() { (cd / && "$MISE_BIN" "$@"); }

# desktop_file ID -- print the path of an installed .desktop file.
desktop_file() {
  local base f
  local -a bases
  IFS=: read -ra bases <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for base in "${XDG_DATA_HOME:-$HOME/.local/share}" "${bases[@]}"; do
    f="${base%/}/applications/$1"
    if [[ -f $f ]]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

read_state() {
  step "File types"
  local t a id
  while read -r t; do KNOWN[$t]=1; done <"$MIME_DIR/types"
  while read -r a t; do ALIAS[$a]=$t; done <"$MIME_DIR/aliases"
  if [[ -f $MIMEAPPS ]]; then
    while IFS='=' read -r t id; do
      [[ -n $t ]] || continue
      t=${ALIAS[$t]:-$t}
      CURRENT[$t]=${id%%;*}
    done < <(awk "$AWK_DEFAULTS" "$MIMEAPPS")
  fi
  info "${#CURRENT[@]} defaults in $(pretty "$MIMEAPPS")"
  if [[ -f $KDE_MIMEAPPS ]]; then
    warn "$(pretty "$KDE_MIMEAPPS") exists; in Plasma it overrides" \
      "mimeapps.list, so check it for these types"
  fi
}

n_types() { if (($1 == 1)); then echo "1 type"; else echo "$1 types"; fi; }

_gio_defaults() { # desktop-id type...
  local id=$1 t
  shift
  for t; do gio mime "$t" "$id"; done
}

# set_defaults LABEL DESKTOP-ID TYPE... -- make DESKTOP-ID the default
# for each TYPE that opens with something else. Types are canonicalized;
# ones the MIME database doesn't know are skipped with a warning.
set_defaults() {
  local label=$1 id=$2 t cur
  shift 2
  local -A seen=()
  local -a todo=() replaced=()
  for t; do
    t=${ALIAS[$t]:-$t}
    [[ -z ${seen[$t]:-} ]] || continue
    seen[$t]=1
    if [[ -z ${KNOWN[$t]:-} ]]; then
      warn "$t is not in the MIME database; skipped"
      continue
    fi
    cur=${CURRENT[$t]:-}
    [[ $cur != "$id" ]] || continue
    todo+=("$t")
    [[ -z $cur ]] || replaced+=("$t (was $cur)")
  done

  if ((${#todo[@]} == 0)); then
    skip "$label is already the default ($(n_types "${#seen[@]}"))"
    return 0
  fi
  apply "$label: default for ${#todo[@]} of $(n_types "${#seen[@]}")" \
    _gio_defaults "$id" "${todo[@]}"
  for t in "${replaced[@]}"; do detail "$t"; done
  DEFAULTS_CHANGED=1
}

configure_gearlever() {
  step "AppImages: Gear Lever"
  if ! desktop_file "$GEARLEVER_DESKTOP" >/dev/null; then
    warn "Gear Lever is not installed (10-apps.sh installs it);" \
      "AppImage defaults left alone"
    return 0
  fi
  set_defaults "Gear Lever" "$GEARLEVER_DESKTOP" "${APPIMAGE_TYPES[@]}"
}

configure_neovim() {
  step "Text and code: Neovim in Ghostty"
  local -a missing=()
  have ghostty || missing+=("Ghostty (07-dev-toolshed.sh installs it)")
  if [[ ! -x $MISE_BIN ]]; then
    missing+=("mise (07-dev-toolshed.sh installs it)")
  elif ! mise_at_root which nvim >/dev/null 2>&1; then
    missing+=("Neovim (07-dev-toolshed.sh installs it)")
  fi
  if ((${#missing[@]})); then
    local m
    for m in "${missing[@]}"; do warn "$m is not installed"; done
    info "text and code defaults left alone"
    return 0
  fi

  link_conf "applications/$NVIM_DESKTOP" "$APPS_DIR/$NVIM_DESKTOP"
  if ((LINK_CHANGED)); then DEFAULTS_CHANGED=1; fi

  local -A excluded=()
  local -a types=()
  local t
  for t in "${TEXT_EXCLUDE[@]}"; do excluded[$t]=1; done
  while read -r t; do
    [[ -n ${excluded[$t]:-} ]] || types+=("$t")
  done < <(awk "$AWK_TEXT_TYPES" "$MIME_DIR/subclasses" | sort)
  types+=("${CODE_TYPES[@]}")
  set_defaults "Neovim" "$NVIM_DESKTOP" "${types[@]}"
}

# declared_types FILE PREFIX... -- print the types a .desktop file
# declares under each PREFIX (image/, video/, ...), canonicalized. Types
# the MIME database doesn't know are dropped quietly.
declared_types() {
  local file=$1 t
  shift
  while read -r t; do
    t=${ALIAS[$t]:-$t}
    [[ -z ${KNOWN[$t]:-} ]] || printf '%s\n' "$t"
  done < <(awk -F= -v prefixes="$*" "$AWK_DECLARED_TYPES" "$file")
}

configure_okular() {
  step "Images: Okular"
  local file
  if ! file=$(desktop_file "$OKULAR_DESKTOP"); then
    warn "Okular is not installed (apt install okular);" \
      "image defaults left alone"
    return 0
  fi
  local -a types=()
  mapfile -t types < <(declared_types "$file" image/)
  set_defaults "Okular" "$OKULAR_DESKTOP" "${types[@]}"
}

configure_vlc() {
  step "Video and audio: VLC"
  local file
  if ! file=$(desktop_file "$VLC_DESKTOP"); then
    warn "VLC is not installed (10-apps.sh installs it);" \
      "video and audio defaults left alone"
    return 0
  fi
  local -a types=()
  mapfile -t types < <(declared_types "$file" video/ audio/)
  set_defaults "VLC" "$VLC_DESKTOP" "${types[@]}" "${VLC_EXTRA_TYPES[@]}"
}

refresh_cache() {
  ((DEFAULTS_CHANGED)) || return 0
  step "KDE cache"
  apply "rebuild the app cache (kbuildsycoca6)" kbuildsycoca6
}

main() {
  lib_init "Default apps to open files with" "$@"
  no_extra_args
  require_user
  require_cmd gio kbuildsycoca6

  read_state
  configure_gearlever
  configure_neovim
  configure_okular
  configure_vlc
  refresh_cache
}

main "$@"
