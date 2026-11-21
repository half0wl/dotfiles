#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 20-kde-config-font.sh
#
# Inter as the UI font everywhere for this user: KDE/Qt apps, window
# titles, GTK apps (Firefox, GNOME apps) and anything that asks fontconfig
# for "sans-serif" (Electron apps, web pages without their own font). The
# fixed-width font is left alone; Inter is not monospaced.
#
# Usage:
#   ./20-kde-config-font.sh [--dry-run] [--yes]
#
#   Run inside Plasma. Log out and back in afterwards so every app picks
#   it up.
#
# Config:
#   ~/.config/fontconfig/conf.d/60-configure-font.conf  (from conf/)
#   kdeglobals, GTK settings.ini, xsettingsd, gsettings (Settings below)
#
# Notes:
#   * KDE keys are written with --notify, which also tells Plasma's GTK
#     sync module; the GTK files are still checked directly in case it
#     isn't running.
#   * Back to Plasma's default (Noto Sans 10): System Settings -> Text &
#     Fonts -> Fonts -> Defaults -> Apply, and remove the fontconfig link.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

FAMILY="Inter"
SIZE=10
SMALL_SIZE=8

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
FONTCONFIG_LINK="$CONFIG/fontconfig/conf.d/60-configure-font.conf"
GTK_FILES=(
  "$CONFIG/gtk-3.0/settings.ini"
  "$CONFIG/gtk-4.0/settings.ini"
)
XSETTINGSD_FILE="$CONFIG/xsettingsd/xsettingsd.conf"

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

# Qt font string: family,size,pixelSize,styleHint,weight,italic,underline,
# strikeOut,fixedPitch,... (the format Plasma 6 itself writes)
qt_font() { printf '%s,%s,-1,5,400,0,0,0,0,0,0,0,0,0,0,1' "$1" "$2"; }

GTK_FONT="$FAMILY,  $SIZE" # same spacing Plasma's GTK sync uses

check_font() {
  step "Font"
  grep -qxF "$FAMILY" <<<"$(fc-list : family | tr ',' '\n')" ||
    die "'$FAMILY' is not installed (run 09-fonts.sh)"
  ok "$FAMILY $SIZE (small text: $SMALL_SIZE)"
}

configure_kde() {
  step "KDE"
  local k font small
  font=$(qt_font "$FAMILY" "$SIZE")
  small=$(qt_font "$FAMILY" "$SMALL_SIZE")
  for k in font menuFont toolBarFont; do
    kconf_set --notify kdeglobals General "$k" "$font"
  done
  kconf_set --notify kdeglobals General smallestReadableFont "$small"
  kconf_set --notify kdeglobals WM activeFont "$font"
}

configure_gtk() {
  step "GTK"
  local f p cur
  for f in "${GTK_FILES[@]}"; do
    p=$(pretty "$f")
    cur=$(sed -n 's/^gtk-font-name=//p' "$f" 2>/dev/null | tail -n1)
    if [[ -z $cur ]]; then
      skip "$p: no gtk-font-name (managed by Plasma's GTK sync)"
    elif [[ $cur == "$GTK_FONT" ]]; then
      skip "$p: gtk-font-name = $GTK_FONT"
    else
      apply "$p: gtk-font-name $cur → $GTK_FONT" \
        sed -i "s/^gtk-font-name=.*/gtk-font-name=$GTK_FONT/" "$f"
    fi
  done

  p=$(pretty "$XSETTINGSD_FILE")
  cur=$(sed -nE 's/^Gtk\/FontName "(.*)"$/\1/p' "$XSETTINGSD_FILE" \
    2>/dev/null | tail -n1)
  if [[ -z $cur ]]; then
    skip "$p: no Gtk/FontName"
  elif [[ $cur == "$GTK_FONT" ]]; then
    skip "$p: Gtk/FontName = $GTK_FONT"
  else
    apply "$p: Gtk/FontName $cur → $GTK_FONT" \
      sed -i "s|^Gtk/FontName .*|Gtk/FontName \"$GTK_FONT\"|" \
      "$XSETTINGSD_FILE"
  fi

  have gsettings || return 0
  cur=$(gsettings get org.gnome.desktop.interface font-name |
    sed "s/^'//; s/'$//")
  if [[ $cur == "$GTK_FONT" ]]; then
    skip "gsettings font-name = $GTK_FONT"
  else
    apply "gsettings font-name: $cur → $GTK_FONT" \
      gsettings set org.gnome.desktop.interface font-name "$GTK_FONT"
  fi
}

configure_fontconfig() {
  step "fontconfig: sans-serif → $FAMILY"
  LINK_CHANGED=0
  link_conf fontconfig/conf.d/60-configure-font.conf "$FONTCONFIG_LINK"
  if ((LINK_CHANGED)); then
    apply "rebuild font cache" fc-cache -f
  fi
  ((DRY_RUN)) && return 0

  local got
  got=$(fc-match -f '%{family[0]}' sans-serif)
  [[ $got == "$FAMILY" ]] ||
    die "fc-match sans-serif gives '$got', expected '$FAMILY'"
  ok "fc-match sans-serif → $got"
}

finish() {
  if ((KCONF_CHANGED || LINK_CHANGED)) && ((!DRY_RUN)); then
    step "Next"
    info "log out and back in so every app picks up the font"
  fi
  return 0
}

main() {
  lib_init "Inter as the UI font (KDE, GTK, fontconfig)" "$@"
  no_extra_args
  require_user
  require_plasma
  require_cmd kreadconfig6 kwriteconfig6 fc-list fc-match fc-cache

  check_font
  configure_kde
  configure_gtk
  configure_fontconfig
  finish
}

main "$@"
