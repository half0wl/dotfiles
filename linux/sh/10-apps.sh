#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 10-apps.sh
#
# Desktop apps and their apt repos: Ghostty, Sublime Merge, Firefox
# (Mozilla's build), Steam, Little Snitch, Flatpak + Flathub (Gear
# Lever), and the AI CLIs (Claude Code, Ollama, pi).
#
# Usage:
#   ./10-apps.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   ~/.config/ghostty/config                    ghostty/config
#   ~/.config/sublime-merge/Packages/User/Preferences.sublime-settings
#   /etc/apt/sources.list.d/sublime-text.list   apt/sources.list.d/
#   /etc/apt/sources.list.d/mozilla.sources     apt/sources.list.d/
#   /etc/apt/preferences.d/mozilla              apt/preferences.d/ (pin)
#
# Notes:
#   * Signing keys are downloaded once (they are keys, not config).
#   * Steam's repo and key are owned by the steam-launcher package.
#   * Firefox prefs are linked by 11-configure-firefox.sh.
#   * Installers piped from curl only run when the tool is missing.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

GHOSTTY_INSTALLER="https://raw.githubusercontent.com/mkasberg"
GHOSTTY_INSTALLER+="/ghostty-ubuntu/HEAD/install.sh"

SUBLIME_KEY_URL="https://download.sublimetext.com/sublimehq-pub.gpg"
SUBLIME_KEYRING=/etc/apt/trusted.gpg.d/sublimehq-archive.gpg

MOZILLA_KEY_URL="https://packages.mozilla.org/apt/repo-signing-key.gpg"
MOZILLA_KEYRING=/etc/apt/keyrings/packages.mozilla.org.asc

STEAM_DEB_URL="https://cdn.akamai.steamstatic.com/client/installer"
STEAM_DEB_URL+="/steam.deb"

LITTLESNITCH_DEB_URL="https://obdev.at/downloads/littlesnitch-linux"
LITTLESNITCH_DEB_URL+="/littlesnitch_1.1.1_amd64.deb"

APT_APPS=(
  flatpak
  plasma-discover-backend-flatpak
  sublime-merge
  firefox
)

FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATPAKS=(
  it.mijorus.gearlever
)

# name|command it provides|install command
CURL_INSTALLERS=(
  "Claude Code|claude|curl -fsSL https://claude.ai/install.sh | bash"
  "Ollama|ollama|curl -fsSL https://ollama.com/install.sh | sh"
  "pi|pi|curl -fsSL https://pi.dev/install.sh | sh"
)

SOURCES=/etc/apt/sources.list.d
MERGE_PREFS="$HOME/.config/sublime-merge/Packages/User"
MERGE_PREFS+="/Preferences.sublime-settings"

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

REPOS_CHANGED=0

_fetch_key() { # url dest dearmor(0|1)
  local tmp
  tmp=$(mktemp)
  curl -fsSL -o "$tmp" "$1"
  if (($3)); then
    gpg --dearmor <"$tmp" | sudo install -D -m 644 /dev/stdin "$2"
  else
    sudo install -D -m 644 "$tmp" "$2"
  fi
  rm -f -- "$tmp"
}

ensure_key() { # label url dest dearmor
  if [[ -s $3 ]]; then
    skip "$1 signing key already installed"
  else
    apply "$1 signing key → $3" _fetch_key "$2" "$3" "$4"
    REPOS_CHANGED=1
  fi
}

configure_repos() {
  step "apt repos"
  LINK_CHANGED=0
  ensure_key "Sublime HQ" "$SUBLIME_KEY_URL" "$SUBLIME_KEYRING" 1
  link_conf apt/sources.list.d/sublime-text.list \
    "$SOURCES/sublime-text.list"
  ensure_key "Mozilla" "$MOZILLA_KEY_URL" "$MOZILLA_KEYRING" 0
  link_conf apt/sources.list.d/mozilla.sources "$SOURCES/mozilla.sources"
  link_conf apt/preferences.d/mozilla /etc/apt/preferences.d/mozilla

  if [[ $(dpkg --print-foreign-architectures) == *i386* ]]; then
    skip "i386 architecture already enabled (Steam)"
  else
    apply "enable i386 architecture (Steam)" \
      sudo dpkg --add-architecture i386
    REPOS_CHANGED=1
  fi

  if ((REPOS_CHANGED || LINK_CHANGED)); then
    apt_update
  else
    skip "repos unchanged; no package list refresh needed"
  fi
}

install_apt_apps() {
  step "Apps"
  apt_ensure "${APT_APPS[@]}"
  deb_ensure steam-launcher "$STEAM_DEB_URL"
  deb_ensure littlesnitch "$LITTLESNITCH_DEB_URL"
  if pkg_installed littlesnitch || ((!DRY_RUN)); then
    systemd_enable littlesnitch --now
  fi
  if pkg_installed ghostty; then
    skip "ghostty already installed"
  else
    # Fetch inside the command so a dry run downloads nothing.
    apply "install ghostty (mkasberg/ghostty-ubuntu)" \
      bash -c 'script=$(curl -fsSL "$1") && bash -c "$script"' \
      _ "$GHOSTTY_INSTALLER"
  fi
}

link_configs() {
  step "Configs"
  link_conf ghostty/config "$HOME/.config/ghostty/config"
  link_conf sublime-merge/Preferences.sublime-settings "$MERGE_PREFS"
}

install_flatpaks() {
  step "Flatpak"
  if ! have flatpak; then
    would "add Flathub and install ${FLATPAKS[*]}" \
      "(after flatpak is installed)"
    return 0
  fi
  local remotes
  remotes=$(flatpak remotes --columns=name 2>/dev/null || true)
  if grep -qx flathub <<<"$remotes"; then
    skip "Flathub remote already added"
  else
    apply "add Flathub remote" \
      sudo flatpak remote-add --if-not-exists flathub "$FLATHUB_URL"
  fi
  local app
  for app in "${FLATPAKS[@]}"; do
    if flatpak info "$app" >/dev/null 2>&1; then
      skip "flatpak $app already installed"
    else
      apply "flatpak: install $app" \
        sudo flatpak install -y --noninteractive flathub "$app"
    fi
  done
}

# Run a piped-from-curl installer with no controlling terminal: some
# (pi) ask questions on /dev/tty, which the spinner would hide forever;
# without a terminal they take their non-interactive defaults. mise's
# shims go on PATH so installers find the node/npm that 04-shell.sh set
# up, however this script was started.
_run_installer() { # install-command
  PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH" \
    setsid --wait bash -c "set -o pipefail; $1"
}

install_ai_tools() {
  step "AI tools"
  local entry name cmd install
  for entry in "${CURL_INSTALLERS[@]}"; do
    IFS='|' read -r name cmd install <<<"$entry"
    if have "$cmd" || [[ -x $HOME/.local/bin/$cmd ]]; then
      skip "$name already installed"
    else
      apply "install $name" _run_installer "$install"
    fi
  done
}

main() {
  lib_init "Ghostty, Sublime Merge, Firefox, Steam, Flatpak, AI CLIs" "$@"
  no_extra_args
  require_user
  need_sudo
  require_cmd curl gpg

  configure_repos
  install_apt_apps
  link_configs
  install_flatpaks
  install_ai_tools
}

main "$@"
