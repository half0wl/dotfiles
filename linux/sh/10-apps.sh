#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 10-apps.sh
#
# Install essential applications plus the apt repos, signing keys and configs
# they need. The full catalog is under Apps below. Development apps are
# in 07-dev-toolshed.sh.
#
# Usage:
#   ./10-apps.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   /etc/apt/sources.list.d/mozilla.sources     apt/sources.list.d/
#   /etc/apt/preferences.d/mozilla              apt/preferences.d/ (pin)
#
# Notes:
#   * Signing keys are downloaded once (they are keys, not config).
#   * Steam's repo and key are owned by the steam-launcher package.
#   * Firefox prefs are linked by 26-config-app-firefox.sh.
#   * Obsidian has no apt repo and updates itself in-app. Bumping its
#     URL only affects new installs; deb_ensure skips an installed
#     copy.
#
# Apps:
#   Firefox          apt (Mozilla repo, pinned)
#   VLC              apt (Debian)
#   Flatpak          apt (Debian), with the Discover backend
#   Steam            .deb (steam-launcher)
#   Little Snitch    .deb (obdev.at)
#   Obsidian         .deb (obsidianmd/obsidian-releases)
#   Gear Lever       Flatpak (Flathub)

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

MOZILLA_LABEL="Mozilla"
MOZILLA_KEY_URL="https://packages.mozilla.org/apt/repo-signing-key.gpg"
MOZILLA_KEYRING=/etc/apt/keyrings/packages.mozilla.org.asc

STEAM_DEB_URL="https://cdn.akamai.steamstatic.com/client/installer"
STEAM_DEB_URL+="/steam.deb"

LITTLESNITCH_DEB_URL="https://obdev.at/downloads/littlesnitch-linux"
LITTLESNITCH_DEB_URL+="/littlesnitch_1.1.1_amd64.deb"

OBSIDIAN_DEB_URL="https://github.com/obsidianmd/obsidian-releases"
OBSIDIAN_DEB_URL+="/releases/download/v1.15.1/obsidian_1.15.1_amd64.deb"

# .debs with no apt repo: "package|url".
DEB_APPS=(
  "steam-launcher|$STEAM_DEB_URL"
  "littlesnitch|$LITTLESNITCH_DEB_URL"
  "obsidian|$OBSIDIAN_DEB_URL"
)

# Services the apps above run, enabled and started once installed (each
# unit is named after its package).
APP_SERVICES=(
  littlesnitch
)

APT_APPS=(
  flatpak
  plasma-discover-backend-flatpak
  firefox
  vlc
)

FLATPAK_REMOTE=flathub
FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATPAKS=(
  it.mijorus.gearlever
)

SOURCES=/etc/apt/sources.list.d

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

configure_repos() {
  step "apt repos"
  local arch_changed=0
  LINK_CHANGED=0
  KEY_CHANGED=0
  ensure_key "$MOZILLA_LABEL" "$MOZILLA_KEY_URL" "$MOZILLA_KEYRING" 0
  link_conf apt/sources.list.d/mozilla.sources "$SOURCES/mozilla.sources"
  link_conf apt/preferences.d/mozilla /etc/apt/preferences.d/mozilla

  if [[ $(dpkg --print-foreign-architectures) == *i386* ]]; then
    skip "i386 architecture already enabled"
  else
    apply "enable i386 architecture (32-bit apps)" \
      sudo dpkg --add-architecture i386
    arch_changed=1
  fi

  if ((KEY_CHANGED || LINK_CHANGED || arch_changed)); then
    apt_update
  else
    skip "repos unchanged; no package list refresh needed"
  fi
}

install_apt_apps() {
  step "Apps"
  apt_ensure "${APT_APPS[@]}"
  local entry pkg url unit
  for entry in "${DEB_APPS[@]}"; do
    IFS='|' read -r pkg url <<<"$entry"
    deb_ensure "$pkg" "$url"
  done
  for unit in "${APP_SERVICES[@]}"; do
    # In a dry run, only an app that is already installed has its unit.
    if pkg_installed "$unit" || ((! DRY_RUN)); then
      systemd_enable "$unit" --now
    fi
  done
}

install_flatpaks() {
  step "Sandboxed apps"
  if ! have flatpak; then
    would "add the $FLATPAK_REMOTE remote and install ${FLATPAKS[*]}" \
      "(after the apps above are installed)"
    return 0
  fi
  local remotes
  remotes=$(flatpak remotes --columns=name 2>/dev/null || true)
  if grep -qx "$FLATPAK_REMOTE" <<<"$remotes"; then
    skip "$FLATPAK_REMOTE remote already added"
  else
    apply "add the $FLATPAK_REMOTE remote" \
      sudo flatpak remote-add --if-not-exists "$FLATPAK_REMOTE" \
      "$FLATHUB_URL"
  fi
  local app
  for app in "${FLATPAKS[@]}"; do
    if flatpak info "$app" >/dev/null 2>&1; then
      skip "$app already installed"
    else
      apply "install $app" \
        sudo flatpak install -y --noninteractive "$FLATPAK_REMOTE" "$app"
    fi
  done
}

main() {
  lib_init "Essential applications" "$@"
  no_extra_args
  require_user
  need_sudo
  require_cmd curl

  configure_repos
  install_apt_apps
  install_flatpaks
}

main "$@"
