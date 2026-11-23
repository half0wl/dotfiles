#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 25-config-kde-debloat.sh
#
# Remove the KDE / Debian apps I don't use, and hide launchers of packages
# that have to stay. Shows exactly what will be purged and asks first.
#
# Usage:
#   ./25-config-kde-debloat.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   ~/.local/share/applications/<launcher>.desktop
#                                 applications/ (Hidden=true)
#
# Notes:
#   * Packages that a removed metapackage pulled in are marked manually
#     installed first, so autoremove only takes what's listed.
#   * Aborts without changing anything if the purge would take the Plasma
#     desktop itself.
#
# Removed:
#   KDE PIM          akregator, grantlee-editor, kaddressbook, kmail,
#                    korganizer, ktnef, mbox-importer, pim-data-exporter,
#                    sieveeditor
#   KDE apps         dragonplayer, gwenview, juk, kate, kwrite, kcalc,
#                    kdeconnect, kfind, kmag, kmousetool, kmouth,
#                    konqueror, konsole, kontrast, kwalletmanager,
#                    khelpcenter, kinfocenter, plasma-welcome
#   LibreOffice      libreoffice (the metapackage), -draw, -impress,
#                    -math; the rest of the suite (Writer, Calc, ...) stays
#   Other            xterm, firefox-esr (Mozilla's Firefox replaces it)
#
# Hidden:
#   LibreOffice Start Center (libreoffice-startcenter.desktop)

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# Packages to purge (glob patterns allowed). Not installed = skipped.
REMOVE=(
  akregator
  grantlee-editor
  dragonplayer
  gwenview
  khelpcenter
  kinfocenter
  juk
  kaddressbook
  kate
  kwrite
  kcalc
  kdeconnect
  kfind
  kmag
  kmail
  kmousetool
  kmouth
  konqueror
  konsole
  kontrast
  korganizer
  ktnef
  kwalletmanager
  mbox-importer
  pim-data-exporter
  sieveeditor
  plasma-welcome
  xterm
  libreoffice
  libreoffice-draw
  libreoffice-impress
  libreoffice-math
  firefox-esr
)

# Launchers that ship with packages you keep: hidden via conf/applications/.
HIDE=(
  libreoffice-startcenter.desktop
)

# Never purge if any of these would go with it.
PROTECTED='plasma-desktop|plasma-workspace|kwin-wayland|sddm'

APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

installed_targets() {
  dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "${REMOVE[@]}" \
    2>/dev/null | awk '$1 == "ii" {print $2}' | sort -u
}

# Packages apt-get would act on ("Purg"/"Remv" lines of a simulation).
simulated() { # apt-get args...
  apt-get -s "$@" | awk '$1 == "Purg" || $1 == "Remv" {print $2}' |
    sort -u
}

# Keep what removed metapackages pulled in (except what's being removed),
# so autoremove doesn't sweep away apps that aren't listed.
protect_collateral() { # wanted-list pkgs...
  local wanted=$1 direct collateral
  shift
  # Metapackages removed as a side effect (kde-standard, task-kde-desktop)
  direct=$(apt-get -s purge "$@" | awk '$1 == "Purg" {print $2}' | sort -u)
  collateral=$(comm -23 <(echo "$direct") <(echo "$wanted"))
  [[ -n $collateral ]] || return 0

  local -a pulled to_mark
  # shellcheck disable=SC2086  # word-split the package list on purpose
  mapfile -t pulled < <(
    apt-cache depends --installed $collateral |
      awk '/^ *\|?(Depends|Recommends):/ && $2 !~ /^</ {print $2}' |
      sort -u | comm -23 - <(echo "$wanted")
  )
  mapfile -t to_mark < <(
    comm -23 <(printf '%s\n' "${pulled[@]}" | sort -u) \
      <(apt-mark showmanual | sort -u)
  )
  ((${#to_mark[@]})) || return 0
  local msg="apt-mark manual: ${#to_mark[@]} packages pulled in by"
  msg+=" ${collateral//$'\n'/ }"
  apply "$msg" sudo apt-mark manual "${to_mark[@]}"
}

purge_packages() {
  step "Packages"
  local -a pkgs
  mapfile -t pkgs < <(installed_targets)
  if ((${#pkgs[@]} == 0)); then
    skip "none of the listed packages are installed"
    return 0
  fi

  protect_collateral "$(printf '%s\n' "${pkgs[@]}")" "${pkgs[@]}"

  local going blocked
  going=$(simulated purge --autoremove "${pkgs[@]}")
  blocked=$(grep -Ex "$PROTECTED" <<<"$going" | xargs || true)
  if [[ -n $blocked ]]; then
    die "this would remove the Plasma desktop itself ($blocked);" \
      "nothing was purged"
  fi

  info "these $(wc -l <<<"$going") packages will be purged:"
  column -c "${COLUMNS:-78}" <<<"$going" | sed 's/^/      /'
  if ! confirm "Purge them?"; then
    warn "cancelled; nothing was purged"
    return 0
  fi
  apply "apt: purge ${#pkgs[@]} apps (+ autoremove)" \
    sudo DEBIAN_FRONTEND=noninteractive \
    apt-get purge --autoremove -y "${pkgs[@]}"
}

hide_launchers() {
  step "Hidden launchers"
  local d
  for d in "${HIDE[@]}"; do
    link_conf "applications/$d" "$APPS_DIR/$d"
  done
}

main() {
  lib_init "Purge unused KDE apps, hide leftover launchers" "$@"
  no_extra_args
  require_user
  need_sudo

  purge_packages
  hide_launchers
}

main "$@"
