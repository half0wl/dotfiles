#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 07-dev-toolshed.sh
#
# Install development tooling plus the apt repos, signing keys and configs
# it needs: CLI tools, a version manager and the tools it pins, a git
# client, a terminal, AI CLIs, VMs and containers. The full catalog is
# under Tools below.
#
# Usage:
#   ./07-dev-toolshed.sh [--dry-run] [--yes]
#
# Config (symlinked from conf/):
#   ~/.gitconfig ~/.gitignore_global   git/
#   ~/.config/git/hooks                git/hooks/
#   ~/.tmux.conf ~/.config/tmux/plugins
#   ~/.config/nvim                     nvim/
#   ~/.config/mise/config.toml         mise/
#   ~/.config/gh/config.yml            gh/ (prefs only; auth stays out)
#   ~/.claude/CLAUDE.md                ai/CLAUDE.md (-> AGENTS.md)
#   ~/.config/ghostty/config           ghostty/config
#   ~/.config/sublime-merge/Packages/User/Preferences.sublime-settings
#   /etc/apt/sources.list.d/sublime-text.list   apt/sources.list.d/
#
# Notes:
#   * `mise use -g <tool>` edits conf/mise/config.toml through the link.
#   * GitHub auth is manual: gh auth login && gh auth setup-git.
#   * Installers piped from curl only run when the tool is missing.
#   * Incus: log out and back in after the first run, so the incus-admin
#     group applies and `incus` works without sudo.
#   * ufw (03-config-system.sh) owns the firewall, so Incus' own firewall
#     rules are turned off for the bridge, and ufw lets guests reach the
#     host only for DHCP and DNS, and route out to anywhere. This follows
#     the Incus docs (howto/network_bridge_firewalld, "Use another
#     firewall"). Each ufw rule is checked with `ufw --dry-run` first,
#     which reports a rule it already has instead of adding it again.
#   * Podman has no daemon, and its optional API socket/service and
#     timers stay disabled, system-wide and for your user. Debian's
#     package never enables them on a fresh install; this checks anyway.
#     Want the Docker-compatible API socket on demand? Run
#     `systemctl --user start podman.socket` (not `enable`).
#   * smartmontools' daemon (smartd) is stopped and disabled; run
#     `smartctl` by hand when you want a drive's health.
#   * Rootless Podman needs a subordinate UID/GID range for your user in
#     /etc/subuid and /etc/subgid; one is added if missing.
#
# Tools:
#   CLI tools        apt (Debian): git, curl, make, gcc, ripgrep, fd-find,
#                    socat, bubblewrap, libfuse2t64, smartmontools
#   mise             curl installer (mise.run), with the tools it pins in
#                    conf/mise/config.toml (neovim, tmux, gh, node, ...)
#   Sublime Merge    apt (Sublime HQ repo)
#   Ghostty          installer script (mkasberg/ghostty-ubuntu)
#   Claude Code      curl installer (claude.ai)
#   Ollama           curl installer (ollama.com)
#   pi               curl installer (pi.dev)
#   Incus + QEMU     apt (Debian), for VMs and system containers
#   Podman           apt (Debian), rootless

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

CLI_PACKAGES=(
  git
  curl
  socat
  libfuse2t64
  bubblewrap
  fd-find
  make
  gcc
  ripgrep
  smartmontools
)
# Services the CLI packages enable on install that should stay off.
CLI_UNITS=(
  smartmontools.service
)

MISE_BIN="$HOME/.local/bin/mise"
MISE_INSTALLER="https://mise.run"

GIT_CLIENT_PACKAGES=(
  sublime-merge
)
SUBLIME_LABEL="Sublime HQ"
SUBLIME_KEY_URL="https://download.sublimetext.com/sublimehq-pub.gpg"
SUBLIME_KEYRING=/etc/apt/trusted.gpg.d/sublimehq-archive.gpg
MERGE_PREFS="$HOME/.config/sublime-merge/Packages/User"
MERGE_PREFS+="/Preferences.sublime-settings"

TERMINAL_PACKAGE=ghostty
GHOSTTY_INSTALLER="https://raw.githubusercontent.com/mkasberg"
GHOSTTY_INSTALLER+="/ghostty-ubuntu/HEAD/install.sh"

# name|command it provides|install command
CURL_INSTALLERS=(
  "Claude Code|claude|curl -fsSL https://claude.ai/install.sh | bash"
  "Ollama|ollama|curl -fsSL https://ollama.com/install.sh | sh"
  "pi|pi|curl -fsSL https://pi.dev/install.sh | sh"
)

VM_PACKAGES=(
  incus
  qemu-system-x86
)
BRIDGE=incusbr0
VM_GROUP=incus-admin

PODMAN_PACKAGES=(
  podman
)
# Units that would start containers (or their API) at boot or login.
PODMAN_UNITS=(
  podman.socket
  podman.service
  podman-restart.service
  podman-auto-update.timer
)
# Subordinate ID range for rootless containers (if none is set up yet).
SUB_ID_START=100000
SUB_ID_COUNT=65536

# ---------------------------------------------------------------------------
# Steps: CLI tools, configs, versioned tools
# ---------------------------------------------------------------------------

install_packages() {
  step "Packages"
  apt_ensure "${CLI_PACKAGES[@]}"

  # CLI only: no daemons left running.
  local unit
  for unit in "${CLI_UNITS[@]}"; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null ||
      systemctl is-active --quiet "$unit" 2>/dev/null; then
      apply "disable + stop $unit" sudo systemctl disable --now "$unit"
    else
      skip "$unit not enabled or running"
    fi
  done
}

link_configs() {
  step "Configs"
  link_conf git/gitconfig "$HOME/.gitconfig"
  link_conf git/gitignore_global "$HOME/.gitignore_global"
  link_conf git/hooks "$HOME/.config/git/hooks"
  link_conf tmux/tmux.conf "$HOME/.tmux.conf"
  link_conf tmux/plugins "$HOME/.config/tmux/plugins"
  link_conf nvim "$HOME/.config/nvim"
  link_conf mise/config.toml "$HOME/.config/mise/config.toml"
  link_conf gh/config.yml "$HOME/.config/gh/config.yml"
  link_conf ai/CLAUDE.md "$HOME/.claude/CLAUDE.md"
  link_conf ghostty/config "$HOME/.config/ghostty/config"
  link_conf sublime-merge/Preferences.sublime-settings "$MERGE_PREFS"
}

# Run the version manager from / so no project-local config is picked up.
mise_at_root() { (cd / && "$MISE_BIN" "$@"); }

install_mise_tools() {
  step "Versioned tools"
  local version name
  name=$(basename "$MISE_BIN")
  if [[ -x $MISE_BIN ]]; then
    version=$("$MISE_BIN" --version 2>/dev/null | awk '{print $1}')
    skip "$name already installed ($version)"
  else
    apply "install $name ($MISE_INSTALLER)" \
      sh -c 'curl -fsSL "$1" | sh' _ "$MISE_INSTALLER"
  fi
  if ((DRY_RUN)) && [[ ! -x $MISE_BIN ]]; then
    would "install the tools in conf/mise/config.toml"
    return 0
  fi

  # Read conf/ directly so a dry run (before the link exists) is accurate.
  # --dry-run-code exits 1 when something would be installed.
  export MISE_GLOBAL_CONFIG_FILE="$CONF_DIR/mise/config.toml"
  if mise_at_root install --dry-run-code >/dev/null 2>&1; then
    skip "all tools in conf/mise/config.toml already installed"
    return 0
  fi
  local missing
  missing=$(mise_at_root ls --missing 2>/dev/null |
    awk '{print $1}' | sort -u | paste -sd' ' -)
  apply "install ${missing:-missing tools}" \
    mise_at_root install --yes
}

# ---------------------------------------------------------------------------
# Steps: apps
# ---------------------------------------------------------------------------

install_sublime_merge() {
  step "Git client"
  LINK_CHANGED=0
  KEY_CHANGED=0
  ensure_key "$SUBLIME_LABEL" "$SUBLIME_KEY_URL" "$SUBLIME_KEYRING" 1
  link_conf apt/sources.list.d/sublime-text.list \
    /etc/apt/sources.list.d/sublime-text.list
  if ((KEY_CHANGED || LINK_CHANGED)); then
    apt_update
  else
    skip "repo unchanged; no package list refresh needed"
  fi
  apt_ensure "${GIT_CLIENT_PACKAGES[@]}"
}

install_ghostty() {
  step "Terminal"
  if pkg_installed "$TERMINAL_PACKAGE"; then
    skip "$TERMINAL_PACKAGE already installed"
  else
    # Fetch inside the command so a dry run downloads nothing.
    apply "install $TERMINAL_PACKAGE ($GHOSTTY_INSTALLER)" \
      bash -c 'script=$(curl -fsSL "$1") && bash -c "$script"' \
      _ "$GHOSTTY_INSTALLER"
  fi
}

# Run a piped-from-curl installer with no controlling terminal: some ask
# questions on /dev/tty, which the spinner would hide forever; without a
# terminal they take their non-interactive defaults. The version
# manager's shims go on PATH so installers find the runtimes installed
# above, however this script was started.
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

# ---------------------------------------------------------------------------
# Steps: VMs and system containers
# ---------------------------------------------------------------------------

# True if the minimal init already ran (default pool + bridge exist).
incus_initialized() {
  sudo incus storage show default >/dev/null 2>&1 &&
    sudo incus network show "$BRIDGE" >/dev/null 2>&1
}

# ufw_ensure RULE... -- add a host firewall rule unless it is there.
ufw_ensure() {
  local out
  out=$(sudo ufw --dry-run "$@" 2>&1 || true)
  if [[ $out == *"Skipping adding existing rule"* &&
    $out != *"Rules updated"* ]]; then
    skip "firewall: $* already present"
  else
    apply "firewall: $*" sudo ufw "$@"
  fi
}

# The bridge's network, e.g. 10.1.2.1/24 -> 10.1.2.0/24 ("" if off).
bridge_cidr() { # ipv4|ipv6
  local addr
  addr=$(sudo incus network get "$BRIDGE" "$1.address" 2>/dev/null ||
    true)
  local ip=${addr%/*} mask=${addr#*/}
  case $addr in
    "" | none) ;;
    *:*) printf '%s:/%s\n' "${ip%:*}" "$mask" ;;
    *) printf '%s.0/%s\n' "${ip%.*}" "$mask" ;;
  esac
}

install_incus() {
  step "VMs and system containers"
  apt_ensure "${VM_PACKAGES[@]}"
  local init="minimal init (a dir storage pool and the $BRIDGE bridge)"
  if ((DRY_RUN)) && ! have incus; then
    would "$init"
    return 0
  fi
  if incus_initialized; then
    skip "already initialized"
  else
    apply "$init" sudo incus admin init --minimal
  fi

  if grep -qx "$VM_GROUP" <<<"$(id -nG "$USER" | tr ' ' '\n')"; then
    skip "$USER already in group $VM_GROUP"
  else
    apply "add $USER to group $VM_GROUP" \
      sudo usermod -aG "$VM_GROUP" "$USER"
    warn "log out and back in so the $VM_GROUP group applies (no sudo" \
      "needed for VMs then)"
  fi
}

configure_incus_firewall() {
  step "Firewall ($BRIDGE)"
  if ((DRY_RUN)) && ! { have incus && incus_initialized; }; then
    would "turn off the VM manager's firewall on $BRIDGE and add host" \
      "firewall rules"
    return 0
  fi

  # The host firewall owns filtering: turn the VM manager's own rules
  # off for the bridge.
  local fam cur cidr
  for fam in ipv4 ipv6; do
    cur=$(sudo incus network get "$BRIDGE" "$fam.firewall" 2>/dev/null ||
      true)
    if [[ $cur == false ]]; then
      skip "$BRIDGE $fam.firewall = false"
    else
      apply "$BRIDGE $fam.firewall = false" \
        sudo incus network set "$BRIDGE" "$fam.firewall=false"
    fi
  done

  # Guests may reach the host only for DHCP (v4/v6) and DNS...
  ufw_ensure allow in on "$BRIDGE" to any port 67 proto udp
  ufw_ensure allow in on "$BRIDGE" to any port 547 proto udp
  ufw_ensure allow in on "$BRIDGE" to any port 53
  # ...and route out to anywhere.
  for fam in ipv4 ipv6; do
    cidr=$(bridge_cidr "$fam")
    if [[ -z $cidr ]]; then
      skip "$BRIDGE has no $fam network"
      continue
    fi
    ufw_ensure route allow in on "$BRIDGE" from "$cidr"
  done
}

# ---------------------------------------------------------------------------
# Steps: containers
# ---------------------------------------------------------------------------

# podman_unit_enabled system|user UNIT
podman_unit_enabled() {
  local -a scope=()
  if [[ $1 == user ]]; then scope=(--user); fi
  systemctl "${scope[@]}" is-enabled --quiet "$2" 2>/dev/null
}

install_podman() {
  step "Containers"
  apt_ensure "${PODMAN_PACKAGES[@]}"

  # Nothing at boot or login.
  local unit scope
  for scope in system user; do
    for unit in "${PODMAN_UNITS[@]}"; do
      if ! podman_unit_enabled "$scope" "$unit"; then
        skip "$scope $unit not enabled"
      elif [[ $scope == system ]]; then
        apply "disable $unit (system)" sudo systemctl disable "$unit"
      else
        apply "disable $unit (user)" systemctl --user disable "$unit"
      fi
    done
  done
}

configure_rootless() {
  step "Rootless containers"
  local file id last=$((SUB_ID_START + SUB_ID_COUNT - 1))
  for file in /etc/subuid /etc/subgid; do
    id=uids
    if [[ $file == /etc/subgid ]]; then id=gids; fi
    if grep -q "^$USER:" "$file" 2>/dev/null; then
      skip "$file already has a range for $USER"
    else
      apply "$file: $USER:$SUB_ID_START:$SUB_ID_COUNT" \
        sudo usermod "--add-sub$id" "$SUB_ID_START-$last" "$USER"
    fi
  done
}

main() {
  lib_init "Install development tooling" "$@"
  no_extra_args
  require_user
  need_sudo
  require_cmd curl gpg

  install_packages
  link_configs
  install_mise_tools
  install_sublime_merge
  install_ghostty
  install_ai_tools
  install_incus
  configure_incus_firewall
  install_podman
  configure_rootless
}

main "$@"
