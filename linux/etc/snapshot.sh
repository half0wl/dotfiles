#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# snapshot.sh
#
# Record what the setup scripts in sh/ manage, as Markdown, so a snapshot
# taken before running them can be diffed against one taken after.
#
# Usage:
#   ./etc/snapshot.sh --output=FILE.md
#
#   ./etc/snapshot.sh --output=/tmp/before.md
#   # ... run the scripts ...
#   ./etc/snapshot.sh --output=/tmp/after.md
#   diff -u /tmp/before.md /tmp/after.md
#
# Notes:
#   * Read-only, and never asks for sudo. What only root can read is listed
#     at the end of the output as not captured.
#   * One line per item, in a fixed order, no timestamps: the diff shows
#     only what changed.
#   * Package, unit, folder and similar lists are read from each script's
#     Settings block (plain assignments, evaluated in a clean shell), so
#     they can't drift from the scripts. The config links (LINKS) and KDE
#     keys (KDE_KEYS) are listed here: update them when a script changes.
#   * Commands are looked up on a fixed PATH, not the calling shell's, so
#     the before and after runs agree.

set -euo pipefail
# The snapshot is built inside $(...), where bash otherwise turns set -e
# off: without this, a missing setting would go unnoticed.
shopt -s inherit_errexit

USER=${USER:-$(id -un)}

# This script lives in linux/etc/; the repo root is one level up.
REPO="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)"
SH="$REPO/sh"
CONF="$REPO/conf"
CFG="$HOME/.config"
SHARE="$HOME/.local/share"
OUT=""

PATH="$SHARE/mise/shims:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin"
PATH+=":/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

usage() { # the header comment above, minus the first lines
  awk 'NR < 4 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

for arg in "$@"; do
  case $arg in
    --output=*) OUT=${arg#--output=} ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done
if [[ -z $OUT ]]; then
  echo "usage: $0 --output=FILE.md" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
  echo "snapshot: $*" >&2
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

pretty() { printf '%s' "${1/#$HOME/\~}"; }

heading() { printf '\n## %s\n\n' "$1"; }
subheading() { printf '\n### %s\n\n' "$1"; }

# settings SCRIPT NAME -- print NAME (an array, one element per line, or a
# scalar) as sh/SCRIPT.sh's Settings block sets it. Only that block runs,
# in a clean shell; it holds nothing but assignments.
settings() {
  local file="$SH/$1.sh" block
  [[ -f $file ]] || die "sh/$1.sh not found"
  block=$(awk '/^# Settings$/ { f = 1; next } /^# Steps$/ { f = 0 } f' \
    "$file")
  [[ -n $block ]] || die "sh/$1.sh has no Settings block"
  bash --norc --noprofile -c "$block"$'\n'"declare -p $2 >/dev/null \
    2>&1 || exit 3"$'\n'"printf '%s\n' \"\${$2[@]}\"" ||
    die "$2 is not set in sh/$1.sh's Settings block"
}

# load VAR SCRIPT NAME -- settings SCRIPT NAME into array VAR, without
# empty elements. Dies (through set -e) if the setting is missing.
load() {
  local -n _dst=$1
  local _out _x
  _out=$(settings "$2" "$3")
  _dst=()
  while IFS= read -r _x; do
    if [[ -n $_x ]]; then _dst+=("$_x"); fi
  done <<<"$_out"
}

# What a path is right now, in words.
describe() {
  local p=$1
  if [[ -L $p ]]; then
    if [[ -e $p ]]; then
      printf 'symlink → %s' "$(pretty "$(readlink -- "$p")")"
    else
      printf 'BROKEN symlink → %s' "$(pretty "$(readlink -- "$p")")"
    fi
  elif [[ -d $p ]]; then
    printf 'directory'
  elif [[ -f $p ]]; then
    printf 'regular file'
  else
    printf 'missing'
  fi
}

# ---------------------------------------------------------------------------
# Config links
# ---------------------------------------------------------------------------

# "script|destination|target". A target starting with / is absolute,
# otherwise relative to conf/. A "?" before the target marks a link the
# script only makes when nothing else provides it (07's apt sources).
# Links built from a script's array (07's PipeWire files, 12's hidden
# launchers) and Firefox's user.js are added in section_links.
LINKS=(
  "00-default-dirs|$CFG/user-dirs.conf|xdg/user-dirs.conf"
  "00-default-dirs|$CFG/user-dirs.dirs|xdg/user-dirs.dirs"
  "03-system|/etc/apt/apt.conf.d/20auto-upgrades|\
    apt/apt.conf.d/20auto-upgrades"
  "03-system|/etc/apt/apt.conf.d/99keep-all-kernels|\
    apt/apt.conf.d/99keep-all-kernels"
  "03-system|/etc/udev/rules.d/81-disable-onboard-bt.rules|\
    udev/81-disable-onboard-bt.rules"
  "04-storage|/etc/udisks2/mount_options.conf|udisks2/mount_options.conf"
  "05-shell|$HOME/.zshrc|zsh/zshrc"
  "05-shell|$HOME/.zprofile|zsh/zprofile"
  "05-shell|$HOME/.gitconfig|git/gitconfig"
  "05-shell|$HOME/.gitignore_global|git/gitignore_global"
  "05-shell|$CFG/git/hooks|git/hooks"
  "05-shell|$HOME/.tmux.conf|tmux/tmux.conf"
  "05-shell|$CFG/tmux/plugins|tmux/plugins"
  "05-shell|$CFG/nvim|nvim"
  "05-shell|$CFG/mise/config.toml|mise/config.toml"
  "05-shell|$CFG/gh/config.yml|gh/config.yml"
  "05-shell|$HOME/.claude/CLAUDE.md|ai/CLAUDE.md"
  "06-keyd|$CFG/keyd/default.conf|keyd/default.conf"
  "06-keyd|/etc/keyd/default.conf|$CFG/keyd/default.conf"
  "06-keyd|$CFG/keyd/app.conf|keyd/app.conf"
  "06-keyd|$CFG/autostart/keyd-application-mapper.desktop|\
    keyd/keyd-application-mapper.desktop"
  "06-keyd|/usr/local/bin/keyd|/usr/bin/keyd.rvaiya"
  "07-audio|/etc/apt/sources.list.d/debian-non-free.list|\
    ?apt/sources.list.d/debian-non-free.list"
  "07-audio|/etc/apt/sources.list.d/debian-src.sources|\
    ?apt/sources.list.d/debian-src.sources"
  "07-audio|/etc/bluetooth/main.conf|bluetooth/main.conf"
  "11-apps|/etc/apt/sources.list.d/sublime-text.list|\
    apt/sources.list.d/sublime-text.list"
  "11-apps|/etc/apt/sources.list.d/mozilla.sources|\
    apt/sources.list.d/mozilla.sources"
  "11-apps|/etc/apt/preferences.d/mozilla|apt/preferences.d/mozilla"
  "11-apps|$CFG/ghostty/config|ghostty/config"
  "11-apps|$CFG/sublime-merge/Packages/User/Preferences.sublime-settings|\
    sublime-merge/Preferences.sublime-settings"
  "20-kde-config-font|$CFG/fontconfig/conf.d/60-configure-font.conf|\
    fontconfig/conf.d/60-configure-font.conf"
  "25-app-config-firefox|$CFG/ff/user-prefs.js|firefox/user-prefs.js"
  "26-app-config-defaults|$SHARE/applications/nvim-ghostty.desktop|\
    applications/nvim-ghostty.desktop"
)

# The same three lookups as 25-app-config-firefox.sh's find_profile (keep
# them in sync): the install's default, the Default=1 profile, the first.
AWK_INSTALL_DEFAULT='
  /^\[Install/ { f = 1; next }
  /^\[/ { f = 0 }
  f && $1 == "Default" { print $2; exit }'
AWK_PROFILE_DEFAULT='
  /^\[Profile/ { path = "" }
  $1 == "Path" { path = $2 }
  $1 == "Default" && $2 == 1 { print path; exit }'
AWK_FIRST_PROFILE='$1 == "Path" { print $2; exit }'

# The Firefox profile 25 links user.js into, over its PROFILE_ROOTS.
firefox_profile() {
  local roots base ini p prog
  load roots 25-app-config-firefox PROFILE_ROOTS
  for base in "${roots[@]}"; do
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

# link_line SCRIPT DEST TARGET [OPTIONAL] -- one line for a link. Returns
# 0 when DEST already is that link.
link_line() {
  local script=$1 dst=$2 target=$3 optional=${4:-0} verdict rc=1
  [[ $target == /* ]] || target="$CONF/$target"
  if [[ -L $dst && $(readlink -- "$dst") == "$target" ]]; then
    verdict="expected"
    rc=0
  elif ((optional)); then
    verdict="linked by $script only if nothing else provides it"
  else
    verdict="expected after $script: symlink → $(pretty "$target")"
  fi
  printf -- '- `%s`: %s (%s)\n' "$(pretty "$dst")" "$(describe "$dst")" \
    "$verdict"
  return "$rc"
}

section_links() {
  local entry script dst target src wp profile ok=0 total=0
  local -a links resample hide
  links=("${LINKS[@]}")

  wp=$(settings 07-audio WP_SRC)
  links+=("07-audio|$CFG/$wp|$wp")
  load resample 07-audio RESAMPLE_SRCS
  for src in "${resample[@]}"; do links+=("07-audio|$CFG/$src|$src"); done
  load hide 12-kde-debloat HIDE
  for src in "${hide[@]}"; do
    links+=("12-kde-debloat|$SHARE/applications/$src|applications/$src")
  done
  if profile=$(firefox_profile); then
    links+=("25-app-config-firefox|$profile/user.js|$CFG/ff/user-prefs.js")
  fi

  heading "Config links"
  for entry in "${links[@]}"; do
    IFS='|' read -r script dst target <<<"$entry"
    target=${target#"${target%%[! ]*}"} # continuation indent
    if [[ $target == \?* ]]; then
      link_line "$script" "$dst" "${target#\?}" 1 || true
      continue
    fi
    total=$((total + 1))
    if link_line "$script" "$dst" "$target"; then ok=$((ok + 1)); fi
  done
  if [[ -z ${profile:-} ]]; then
    echo '- Firefox `user.js`: no profile found (launch Firefox once)'
  fi
  printf '\n**%s of %s links as the scripts would set them.**\n' \
    "$ok" "$total"

  echo
  echo "Links still pointing at the old repo:"
  local old
  old=$({
    find "$HOME" -maxdepth 5 -xdev -lname '*dotfiles-linux*' 2>/dev/null
    find /etc -maxdepth 4 -lname '*dotfiles-linux*' 2>/dev/null
  } | sort || true)
  if [[ -z $old ]]; then
    echo "- none"
  else
    while IFS= read -r entry; do
      printf -- '- `%s`\n' "$(pretty "$entry")"
    done <<<"$old"
  fi
}

# ---------------------------------------------------------------------------
# KDE settings (20-24)
# ---------------------------------------------------------------------------

# "rc file|group (nested with /)|key", as 20-24 set them. 23's mouse keys
# and unbound launchers come from its Settings and are added below.
KDE_KEYS=(
  "kdeglobals|General|font"
  "kdeglobals|General|menuFont"
  "kdeglobals|General|toolBarFont"
  "kdeglobals|General|smallestReadableFont"
  "kdeglobals|WM|activeFont"
  "dolphinrc|General|GlobalViewProps"
  "dolphinrc|DetailsMode|IconSize"
  "dolphinrc|DetailsMode|PreviewSize"
  "dolphinrc|CompactMode|IconSize"
  "dolphinrc|CompactMode|PreviewSize"
  "dolphinrc|IconsMode|IconSize"
  "dolphinrc|IconsMode|PreviewSize"
  "dolphinrc|IconsMode|TextWidthIndex"
  "dolphinrc|IconsMode|MaximumTextLines"
  "dolphinrc|PlacesPanel|IconSize"
  "kwinrc|Effect-overview|Enabled"
  "kwinrc|Windows|RollOverDesktops"
  "kwinrc|TabBox|DesktopMode"
  "kglobalshortcutsrc|kwin|Overview"
  "kglobalshortcutsrc|kwin|Window Quick Tile Top"
  "kglobalshortcutsrc|kwin|Switch One Desktop to the Left"
  "kglobalshortcutsrc|kwin|Switch One Desktop to the Right"
  "kglobalshortcutsrc|kwin|Window Quick Tile Left"
  "kglobalshortcutsrc|kwin|Window Quick Tile Right"
  "kdeglobals|KDE|AnimationDurationFactor"
  "kcminputrc|Keyboard|RepeatDelay"
  "kcminputrc|Keyboard|RepeatRate"
  "kscreenlockerrc|Daemon|Autolock"
  "kscreenlockerrc|Daemon|Timeout"
  "ksmserverrc|General|loginMode"
  "kwinrc|NightColor|Active"
  "kwinrc|Xwayland|Scale"
  "spectaclerc|ImageSave|imageSaveLocation"
  "spectaclerc|ImageSave|imageFilenameTemplate"
  "spectaclerc|VideoSave|videoSaveLocation"
  "spectaclerc|VideoSave|videoFilenameTemplate"
)

kread() { # file group key
  local -a groups args
  local g
  IFS=/ read -ra groups <<<"$2"
  args=(--file "$1")
  for g in "${groups[@]}"; do args+=(--group "$g"); done
  kreadconfig6 "${args[@]}" --key "$3" 2>/dev/null || true
}

# HiddenFilesShown in Dolphin's global view properties (21), from the
# folder's xattr, or its .directory file where xattrs aren't supported.
dolphin_hidden() {
  python3 -I - "$SHARE/dolphin/view_properties/global" <<'PY'
import configparser, os, sys
d = sys.argv[1]
text = ""
try:
    text = os.getxattr(d, "user.kde.fm.viewproperties#1").decode()
except OSError:
    try:
        with open(os.path.join(d, ".directory")) as f:
            text = f.read()
    except OSError:
        pass
cp = configparser.ConfigParser(interpolation=None, strict=False)
cp.optionxform = str
try:
    cp.read_string(text)
except configparser.Error:
    print("unreadable")
    sys.exit(0)
print(cp.get("Settings", "HiddenFilesShown", fallback="unset"))
PY
}

# Mode, scale and VRR policy of an output (23), as KWin saved them; the
# same reading as 23-kde-config-desktop.sh's current_display.
display_state() { # output
  python3 -I - "$1" "$CFG/kwinoutputconfig.json" <<'PY'
import json, sys
name, path = sys.argv[1:3]
try:
    with open(path) as f:
        blocks = json.load(f)
except (OSError, ValueError):
    print("unknown (no kwinoutputconfig.json)")
    sys.exit(0)
for block in blocks:
    if block.get("name") != "outputs":
        continue
    for o in block.get("data", []):
        if o.get("connectorName") != name:
            continue
        m = o.get("mode", {})
        hz = round(m.get("refreshRate", 0) / 1000)
        print(f"{m.get('width')}x{m.get('height')}@{hz}, scale",
              o.get("scale"), "VRR", str(o.get("vrrPolicy", "")).lower())
        sys.exit(0)
print("not configured")
PY
}

section_kde() {
  heading "KDE settings"
  if ! have kreadconfig6; then
    echo "- kreadconfig6 not installed"
    return 0
  fi

  local entry file group key v out
  local -a keys mice launchers gtk_files
  keys=("${KDE_KEYS[@]}")
  load mice 23-kde-config-desktop MOUSE_SETTINGS
  for entry in "${mice[@]}"; do # group|key|value
    IFS='|' read -r group key _ <<<"$entry"
    keys+=("kcminputrc|$group|$key")
  done
  load launchers 23-kde-config-desktop UNBOUND_LAUNCHERS
  for entry in "${launchers[@]}"; do
    keys+=("kglobalshortcutsrc|services/$entry|_launch")
  done

  for entry in "${keys[@]}"; do
    IFS='|' read -r file group key <<<"$entry"
    v=$(kread "$file" "$group" "$key")
    # Shortcuts are "active,default,description": keep the active one.
    if [[ $file == kglobalshortcutsrc ]]; then v=${v%%,*}; fi
    printf -- '- `%s` [%s] %s: `%s`\n' "$file" "$group" "$key" \
      "${v:-unset}"
  done

  printf -- '- Dolphin view properties, HiddenFilesShown: `%s`\n' \
    "$(dolphin_hidden)"

  load gtk_files 20-kde-config-font GTK_FILES
  gtk_files+=("$(settings 20-kde-config-font XSETTINGSD_FILE)")
  for file in "${gtk_files[@]}"; do
    if [[ ! -f $file ]]; then
      v="missing"
    elif [[ $file == */xsettingsd.conf ]]; then
      v=$(sed -n 's|^Gtk/FontName ||p' "$file" | tail -n 1)
    else
      v=$(sed -n 's/^gtk-font-name=//p' "$file" | tail -n 1)
    fi
    printf -- '- `%s` font: `%s`\n' "$(pretty "$file")" "${v:-unset}"
  done
  v=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null ||
    echo '?')
  printf -- '- gsettings font-name: `%s`\n' "$v"

  v=$(timeout 5 gdbus call --session --dest org.kde.KWin \
    --object-path /VirtualDesktopManager \
    --method org.freedesktop.DBus.Properties.Get \
    org.kde.KWin.VirtualDesktopManager rows 2>/dev/null |
    sed -E 's/.*uint32 ([0-9]+).*/\1/' || true)
  printf -- '- Virtual desktop rows: %s\n' "${v:-unknown (no Plasma session)}"

  out=$(settings 23-kde-config-desktop DISPLAY_OUTPUT)
  if [[ -n $out ]]; then
    printf -- '- Display `%s`: %s\n' "$out" "$(display_state "$out")"
  fi

  for key in IMAGE_DIR VIDEO_DIR; do
    v=$(settings 24-kde-config-spectacle "$key")
    printf -- '- Spectacle folder `%s`: %s\n' "$(pretty "$v")" \
      "$(describe "$v")"
  done
}

# ---------------------------------------------------------------------------
# Packages and services
# ---------------------------------------------------------------------------

# "script|Settings array|packages it installs outside an array".
PKG_SOURCES=(
  "01-update|BASE_PACKAGES|"
  "02-nvidia|DRIVER_PACKAGES|cuda-keyring"
  "03-system|UPDATE_PACKAGES|ufw"
  "04-storage|APFS_PACKAGES|"
  "05-shell|PACKAGES|"
  "06-keyd||keyd"
  "07-audio|BUILD_DEPS|libfdk-aac-dev"
  "08-qemu-vmm|PACKAGES|"
  "09-podman|PACKAGES|"
  "10-fonts|APT_FONTS|"
  "11-apps|APT_APPS|steam-launcher littlesnitch obsidian ghostty"
  "12-kde-debloat|REMOVE|"
  "25-app-config-firefox|PACKAGES|"
)

# Services the scripts enable, disable or rely on (09's come from UNITS).
SYSTEM_UNITS=(keyd fstrim.timer littlesnitch sddm ufw)

pkg_state() {
  local s
  s=$(dpkg-query -W -f='${db:Status-Abbrev} ${Version}' "$1" \
    2>/dev/null || true)
  case $s in
    ii*)
      s=${s#ii}
      printf 'installed %s' "${s#"${s%%[! ]*}"}"
      ;;
    rc*) printf 'removed (config left)' ;;
    *) printf 'not installed' ;;
  esac
}

section_packages() {
  local entry script arr extra p
  local -a pkgs extra_pkgs
  heading "Packages"
  for entry in "${PKG_SOURCES[@]}"; do
    IFS='|' read -r script arr extra <<<"$entry"
    pkgs=()
    if [[ -n $arr ]]; then load pkgs "$script" "$arr"; fi
    read -ra extra_pkgs <<<"$extra"
    pkgs+=("${extra_pkgs[@]}")
    if [[ $script == 12-kde-debloat ]]; then
      subheading "$script (purges these)"
    else
      subheading "$script"
    fi
    for p in "${pkgs[@]}"; do
      printf -- '- `%s`: %s\n' "$p" "$(pkg_state "$p")"
    done
  done
}

unit_state() { # [--user] unit
  local -a scope=()
  if [[ $1 == --user ]]; then
    scope=(--user)
    shift
  fi
  printf '%s, %s' \
    "$(systemctl "${scope[@]}" is-enabled "$1" 2>/dev/null || true)" \
    "$(systemctl "${scope[@]}" is-active "$1" 2>/dev/null || true)"
}

section_services() {
  local u
  local -a podman_units
  load podman_units 09-podman UNITS
  heading "Services"
  for u in "${SYSTEM_UNITS[@]}" "${podman_units[@]}"; do
    printf -- '- `%s`: %s\n' "$u" "$(unit_state "$u")"
  done
  for u in "${podman_units[@]}"; do
    printf -- '- `%s` (user): %s\n' "$u" "$(unit_state --user "$u")"
  done
}

# ---------------------------------------------------------------------------
# User
# ---------------------------------------------------------------------------

section_user() {
  local g entry name cmd tools
  local -a installers
  heading "User"
  printf -- '- Login shell: `%s`\n' "$(getent passwd "$USER" | cut -d: -f7)"
  # The group database, not this session: usermod shows up before a
  # re-login. (A here-string, not a pipe into grep -q: with pipefail, a
  # writer killed by grep's early exit would read as "not a member".)
  for g in keyd incus-admin; do
    if grep -qx "$g" <<<"$(id -nG "$USER" | tr ' ' '\n')"; then
      printf -- '- Group `%s`: member\n' "$g"
    else
      printf -- '- Group `%s`: not a member\n' "$g"
    fi
  done

  load installers 11-apps CURL_INSTALLERS
  for entry in "mise|mise" "${installers[@]}"; do # name|command|...
    IFS='|' read -r name cmd _ <<<"$entry"
    if have "$cmd"; then
      printf -- '- %s (`%s`): installed\n' "$name" "$cmd"
    else
      printf -- '- %s (`%s`): not installed\n' "$name" "$cmd"
    fi
  done

  echo
  echo "mise tools (from 05-shell):"
  if ! have mise; then
    echo "- mise not installed"
    return 0
  fi
  tools=$(timeout 60 mise ls --installed 2>/dev/null |
    awk '{ print $1, $2 }' | sort || true)
  if [[ -z $tools ]]; then
    echo "- none"
  else
    while IFS= read -r entry; do
      printf -- '- `%s`\n' "$entry"
    done <<<"$tools"
  fi
}

# ---------------------------------------------------------------------------
# System state, by script
# ---------------------------------------------------------------------------

# Kernels as 02-nvidia.sh finds them: the ones in /boot. /lib/modules can
# hold leftovers of removed kernels.
kernels() {
  find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' |
    sed 's/^vmlinuz-//' | sort -V
}

nvidia_module() { # kernel
  local signer
  if ! modinfo -k "$1" nvidia >/dev/null 2>&1; then
    printf 'no NVIDIA module'
    return 0
  fi
  signer=$(modinfo -k "$1" -F signer nvidia 2>/dev/null || true)
  printf 'NVIDIA module %s' "${signer:+signed by $signer}"
  [[ -n $signer ]] || printf 'unsigned'
}

system_kernels() {
  local k n
  local -a upgrade_opts
  subheading "01-update, 02-nvidia"
  printf -- '- Running kernel: `%s`\n' "$(uname -r)"
  while IFS= read -r k; do
    printf -- '- Kernel `%s`: headers %s, %s\n' "$k" \
      "$(pkg_state "linux-headers-$k")" "$(nvidia_module "$k")"
  done < <(kernels)
  if have mokutil; then
    k=$(mokutil --sb-state 2>/dev/null | awk 'NR == 1' || true)
    printf -- '- Secure Boot: %s\n' "${k:-unknown}"
  fi
  if have dkms; then
    while IFS= read -r k; do
      if [[ -n $k ]]; then printf -- '- DKMS: `%s`\n' "$k"; fi
    done < <(dkms status 2>/dev/null | sort || true)
  fi
  load upgrade_opts 01-update APT_UPGRADE_OPTS
  # A simulation, against the package lists as they are now.
  n=$(apt-get -s -o Debug::NoLocking=1 "${upgrade_opts[@]}" full-upgrade \
    2>/dev/null | grep -c '^Inst ' || true)
  printf -- '- Pending upgrades: %s\n' "${n:-0}"
}

system_03() {
  local locale norm lang vendor product d found=""
  subheading "03-system"
  printf -- '- Default target: `%s`\n' "$(systemctl get-default)"

  locale=$(settings 03-system LOCALE)
  norm="${locale%%.*}.$(tr '[:upper:]' '[:lower:]' <<<"${locale#*.}" |
    tr -d -)"
  if grep -qix "$norm" <<<"$(locale -a 2>/dev/null)"; then
    printf -- '- Locale `%s`: generated\n' "$locale"
  else
    printf -- '- Locale `%s`: not generated\n' "$locale"
  fi
  lang=$(grep -E '^LANG=' /etc/default/locale 2>/dev/null || true)
  printf -- '- /etc/default/locale: `%s`\n' "${lang:-no LANG}"

  printf -- '- ufw: `%s`\n' "$(grep -E '^ENABLED=' /etc/ufw/ufw.conf \
    2>/dev/null || echo 'not installed')"
  grep -E '^DEFAULT_(INPUT|OUTPUT)_POLICY=' /etc/default/ufw 2>/dev/null |
    sed 's/.*/- ufw `&`/' || true

  vendor=$(settings 03-system BT_VENDOR)
  product=$(settings 03-system BT_PRODUCT)
  for d in /sys/bus/usb/devices/*; do
    [[ -f $d/idVendor && -f $d/idProduct ]] || continue
    [[ $(<"$d/idVendor") == "$vendor" ]] || continue
    [[ $(<"$d/idProduct") == "$product" ]] || continue
    found="authorized=$(<"$d/authorized")"
  done
  printf -- '- Onboard Bluetooth %s:%s: %s\n' "$vendor" "$product" \
    "${found:-not present}"

  printf -- '- /boot: %s used\n' \
    "$(df --output=pcent /boot 2>/dev/null | tail -n 1 | tr -d ' ')"
  printf -- '- Old udev rule 81-disable-internal-bt.rules: %s\n' \
    "$(describe /etc/udev/rules.d/81-disable-internal-bt.rules)"
}

system_04() {
  local vols v
  subheading "04-storage"
  # The same volume and option matching as 04-storage.sh.
  vols=$(awk '!/^[[:space:]]*(#|$)/ && NF >= 3 {
      print $1 ": " ($4 ~ /(^|,)discard(,|$)/ ? "discard" : "no discard")
    }' /etc/crypttab 2>/dev/null || true)
  if [[ -z $vols ]]; then
    echo "- crypttab: no encrypted volumes"
  else
    while IFS= read -r v; do printf -- '- crypttab %s\n' "$v"; done \
      <<<"$vols"
  fi
  printf -- '- /etc/crypttab.bak: %s\n' "$(describe /etc/crypttab.bak)"
  # (free - available) / total: what tune2fs reports, give or take
  # rounding (tune2fs itself needs root).
  printf -- '- Root filesystem reserve: %s\n' "$(stat -f -c '%b %f %a' / |
    awk '{ printf "%.1f%%", ($2 - $3) * 100 / $1 }')"
}

system_06_to_11() {
  local mapper plugin sbc stamp built pw bridge fam dir font_dir name app
  local -a fams flatpaks
  subheading "06-keyd"
  mapper=$(settings 06-keyd MAPPER_BIN)
  printf -- '- `%s`: %s\n' "$mapper" "$(describe "$mapper")"

  subheading "07-audio"
  if dpkg-query -W libspa-0.2-bluetooth >/dev/null 2>&1; then
    sbc=$(dpkg -L libspa-0.2-bluetooth |
      grep 'libspa-codec-bluez5-sbc\.so$' || true)
    plugin="$(dirname "${sbc:-/missing}")/libspa-codec-bluez5-aac.so"
    printf -- '- AAC plugin `%s`: %s\n' "$plugin" "$(describe "$plugin")"
    pw=$(dpkg-query -W -f='${Version}' libspa-0.2-bluetooth)
  else
    echo "- AAC plugin: libspa-0.2-bluetooth not installed"
    pw="none"
  fi
  stamp=$(settings 07-audio STAMP)
  built=$(cat "$stamp" 2>/dev/null || echo "never")
  printf -- '- AAC plugin built for PipeWire `%s` (installed: `%s`)\n' \
    "$built" "$pw"

  subheading "08-qemu-vmm"
  bridge=$(settings 08-qemu-vmm BRIDGE)
  if ip link show "$bridge" >/dev/null 2>&1; then
    printf -- '- Bridge `%s`: present\n' "$bridge"
  else
    printf -- '- Bridge `%s`: missing\n' "$bridge"
  fi
  printf -- '- Incus storage pool `default`: %s\n' \
    "$(describe /var/lib/incus/storage-pools/default)"

  subheading "09-podman"
  printf -- '- /etc/subuid: `%s`\n' \
    "$(grep "^$USER:" /etc/subuid 2>/dev/null || echo none)"
  printf -- '- /etc/subgid: `%s`\n' \
    "$(grep "^$USER:" /etc/subgid 2>/dev/null || echo none)"

  subheading "10-fonts"
  load fams 10-fonts MONASPACE_FAMILIES
  font_dir=$(settings 10-fonts FONT_DIR)
  for fam in "${fams[@]}"; do
    dir="$font_dir/monaspace-${fam,,}"
    printf -- '- `%s`: %s, %s file(s)\n' "$(pretty "$dir")" \
      "$(describe "$dir")" "$(find "$dir" -type f 2>/dev/null | wc -l)"
  done

  subheading "11-apps"
  printf -- '- Foreign architectures: `%s`\n' \
    "$(dpkg --print-foreign-architectures | paste -sd' ' -)"
  for name in SUBLIME_KEYRING MOZILLA_KEYRING; do
    dir=$(settings 11-apps "$name")
    printf -- '- `%s`: %s\n' "$dir" "$(describe "$dir")"
  done
  if have flatpak; then
    printf -- '- Flatpak remotes: `%s`\n' "$(flatpak remotes \
      --columns=name,options 2>/dev/null | sort | tr '\t\n' ': ' |
      sed 's/ $//')"
    load flatpaks 11-apps FLATPAKS
    for app in "${flatpaks[@]}"; do
      if flatpak info "$app" >/dev/null 2>&1; then
        printf -- '- Flatpak `%s`: installed\n' "$app"
      else
        printf -- '- Flatpak `%s`: not installed\n' "$app"
      fi
    done
  else
    echo "- flatpak not installed"
  fi
}

section_system() {
  heading "System"
  system_kernels
  system_03
  system_04
  system_06_to_11
  subheading "All scripts"
  printf -- '- Backups in ~/.local/state/dotfiles-bak: %s file(s)\n' \
    "$(find "$HOME/.local/state/dotfiles-bak" -type f 2>/dev/null |
      wc -l)"
}

# ---------------------------------------------------------------------------
# Home folders (00)
# ---------------------------------------------------------------------------

section_home() {
  local d
  local -a create remove
  load create 00-default-dirs CREATE
  load remove 00-default-dirs DIRS
  heading "Home folders"
  for d in "${create[@]}"; do
    printf -- '- `~/%s`: %s (kept)\n' "$d" "$(describe "$HOME/$d")"
  done
  for d in "${remove[@]}"; do
    printf -- '- `~/%s`: %s (removed by 00)\n' "$d" "$(describe "$HOME/$d")"
  done
  # Where each XDG dir resolves to: what apps actually get.
  for d in DESKTOP DOWNLOAD DOCUMENTS MUSIC PICTURES VIDEOS TEMPLATES \
    PUBLICSHARE; do
    printf -- '- XDG `%s`: `%s`\n' "$d" \
      "$(pretty "$(xdg-user-dir "$d" 2>/dev/null || echo '?')")"
  done
}

# ---------------------------------------------------------------------------
# Not captured
# ---------------------------------------------------------------------------

section_not_captured() {
  heading "Not captured"
  cat <<'EOF'
Check these by hand; reading them needs root or a live service:

- ufw rules, including 08's rules for the Incus bridge
  (`sudo ufw status verbose`)
- Incus' own firewall on the bridge, off by 08
  (`incus network get incusbr0 ipv4.firewall`, needs incus-admin in the
  current session)
- whether the DKMS signing key is enrolled
  (`sudo mokutil --test-key /var/lib/dkms/mok.pub`)
- the exact ext4 reserve (`sudo tune2fs -l /dev/vg0/root`)
- that the initramfs has crypttab's `discard` (rebuilt by 04)
- pending firmware updates (`fwupdmgr get-updates`)
- Dolphin's Information panel (21): it lives in Dolphin's window state,
  which also changes on its own
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

snapshot() {
  echo "# System snapshot"
  echo
  echo "Repo: \`$(pretty "$REPO")\`"
  section_links
  section_kde
  section_packages
  section_services
  section_user
  section_system
  section_home
  section_not_captured
}

# Build it in full before writing, so a failure leaves no partial file.
# cat -s: one blank line between sections, however they end.
content=$(snapshot)
printf '%s\n' "$content" | cat -s >"$OUT"
echo "wrote $OUT"
