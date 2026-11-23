#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 05-config-bt-audio.sh
#
# Best Bluetooth sound for AirPods Max 2 on PipeWire: AAC instead of SBC.
#
#   1. Builds PipeWire's AAC codec plugin against fdk-aac (Debian ships it
#      without) for the installed PipeWire version. Skipped if built.
#   2. Links the WirePlumber / PipeWire configs: AAC > SBC, SBC-XQ off
#      (AirPods Max 2 play only the left channel with it), AAC at CBR, no
#      automatic switch to the headset (HFP) profile, resampler quality 10.
#   3. Restarts the audio services only if 1 or 2 changed anything,
#      switches connected headphones to AAC, and verifies the whole chain.
#
# Usage:
#   ./05-config-bt-audio.sh [--dry-run] [--yes]
#
#   Connect the AirPods Max 2 first so the per-device checks can run.
#   Exit code 1 means a check failed (see the red lines).
#
# Config (symlinked from conf/):
#   ~/.config/wireplumber/wireplumber.conf.d/51-bluez-aac.conf
#   ~/.config/pipewire/{pipewire-pulse,client}.conf.d/10-resample.conf
#   /etc/apt/sources.list.d/debian-non-free.list   (for libfdk-aac-dev)
#   /etc/apt/sources.list.d/debian-src.sources     (for build-dep)
#   /etc/bluetooth/main.conf   BLE connection intervals (low latency)
#   Each apt source is only linked if no other source already provides
#   it: duplicates make apt warn on every update.
#
# Notes:
#   * Re-run after every PipeWire upgrade: a plugin built for another
#     version may not load. The build stamp makes this automatic.
#   * Audio cuts out briefly when the services restart. Bluetooth itself
#     is only restarted when main.conf's contents change.
#   * Undo: remove the links above and delete libspa-codec-bluez5-aac.so
#     next to libspa-codec-bluez5-sbc.so (dpkg -L libspa-0.2-bluetooth).

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

# Lowest negotiated AAC bitrate the verification accepts (AirPods Max 2:
# 256k).
AAC_MIN_BITRATE=256000

WP_SRC=wireplumber/wireplumber.conf.d/51-bluez-aac.conf
RESAMPLE_SRCS=(
  pipewire/pipewire-pulse.conf.d/10-resample.conf # PulseAudio apps
  pipewire/client.conf.d/10-resample.conf         # native PipeWire apps
)
SOURCES_D=/etc/apt/sources.list.d
BT_CONF=/etc/bluetooth/main.conf

BUILD_DEPS=(
  dpkg-dev
  meson
  ninja-build
  pkg-config
)
TMP_PREFIX="pipewire-aac-build"
STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/pipewire-aac/built-for"
PW_TARBALLS="https://gitlab.freedesktop.org/pipewire/pipewire/-/archive"

# ---------------------------------------------------------------------------
# Python helpers (read pw-dump JSON on stdin)
# ---------------------------------------------------------------------------

# Print "<app>\t<resample.quality>" for every playing output stream.
read -r -d '' PY_STREAMS <<'PY' || true
import json, sys
for o in json.load(sys.stdin):
    info = o.get("info") or {}
    p = info.get("props") or {}
    if p.get("media.class") != "Stream/Output/Audio":
        continue
    for pr in (info.get("params") or {}).get("Props", []):
        v = pr.get("params")
        if isinstance(v, list) and "resample.quality" in v:
            name = p.get("application.name") or p.get("node.name")
            print(name, v[v.index("resample.quality") + 1], sep="\t")
            break
PY

# Print bluez5.a2dp.aac.bitratemode of device argv[1].
read -r -d '' PY_BITRATEMODE <<'PY' || true
import json, sys
for o in json.load(sys.stdin):
    p = (o.get("info") or {}).get("props") or {}
    if p.get("device.name") == sys.argv[1]:
        print(p.get("bluez5.a2dp.aac.bitratemode", "unset"))
        break
PY

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

PW_VER_DEB=""
PLUGIN=""
RESAMPLE_QUALITY=""
AAC_BITRATEMODE=""
RESTART_NEEDED=0
FAIL=0

# conf_value FILE KEY -- the number assigned to KEY in a conf/ file.
conf_value() {
  local sp='[[:space:]]*' key=${2//./\\.}
  sed -nE "s/^${sp}${key}${sp}=${sp}([0-9]+).*/\1/p" "$CONF_DIR/$1"
}

read_expected() {
  # The values to verify come from the conf files themselves.
  RESAMPLE_QUALITY=$(conf_value "${RESAMPLE_SRCS[1]}" resample.quality)
  AAC_BITRATEMODE=$(conf_value "$WP_SRC" bluez5.a2dp.aac.bitratemode)
  [[ -n $RESAMPLE_QUALITY && -n $AAC_BITRATEMODE ]] ||
    die "could not read expected values from conf/"
}

locate_plugin() {
  pkg_installed libspa-0.2-bluetooth ||
    die "libspa-0.2-bluetooth is not installed (PipeWire Bluetooth)"
  PW_VER_DEB=$(dpkg-query -W -f='${Version}' libspa-0.2-bluetooth)
  local sbc
  sbc=$(dpkg -L libspa-0.2-bluetooth | grep 'libspa-codec-bluez5-sbc\.so$')
  PLUGIN="$(dirname "$sbc")/libspa-codec-bluez5-aac.so"
}

link_configs() {
  step "Configs"
  link_apt_source debian-non-free.list Packages non-free
  link_apt_source debian-src.sources Sources main
  link_bluetooth_conf
  LINK_CHANGED=0
  link_conf "$WP_SRC" "$HOME/.config/$WP_SRC"
  local src
  for src in "${RESAMPLE_SRCS[@]}"; do
    link_conf "$src" "$HOME/.config/$src"
  done
  ((LINK_CHANGED)) && RESTART_NEEDED=1
  return 0
}

# bluetoothd reads main.conf at startup: restart it only when the
# contents change (replacing an identical copy with the link doesn't).
link_bluetooth_conf() {
  local differs=0
  cmp -s "$BT_CONF" "$CONF_DIR/bluetooth/main.conf" || differs=1
  link_conf bluetooth/main.conf "$BT_CONF"
  if ((differs)); then
    apply "restart bluetooth (main.conf changed)" \
      sudo systemctl restart bluetooth
  fi
}

# The sources file that provides KIND (Packages, Sources) for COMPONENT,
# leaving FILE out. Empty if none. apt drops duplicate entries from its
# view, so FILE is left out of the sources apt reads, not just filtered
# from the answer: otherwise a duplicate that FILE shadows is never seen.
apt_provider() { # kind component file-to-leave-out
  local parts f entry
  parts=$(mktemp -d)
  for f in "$SOURCES_D"/*.list "$SOURCES_D"/*.sources; do
    [[ -e $f && $f != "$3" ]] && ln -s "$f" "$parts/"
  done
  entry=$(apt-get -o Dir::Etc::SourceParts="$parts" indextargets \
    --format '$(CREATED_BY) $(COMPONENT) $(SOURCESENTRY)' |
    awk -v k="$1" -v c="$2" '$1 == k && $2 == c { print $3; exit }')
  find "$parts" -mindepth 1 -maxdepth 1 -type l -delete
  rmdir "$parts"
  entry=${entry%:*}
  # Report the real path, not the temporary link.
  [[ $entry == "$parts"/* ]] && entry="$SOURCES_D/${entry#"$parts"/}"
  printf '%s\n' "$entry"
}

# Link conf/apt/sources.list.d/NAME unless another source already provides
# the same KIND + COMPONENT; drop our own link if it is a duplicate.
link_apt_source() { # name kind component
  local name=$1 kind=$2 comp=$3 dst="$SOURCES_D/$1" other ours
  ours="$CONF_DIR/apt/sources.list.d/$name"
  other=$(apt_provider "$kind" "$comp" "$dst")
  if [[ -z $other ]]; then
    link_conf "apt/sources.list.d/$name" "$dst"
    return 0
  fi
  skip "apt: $kind $comp already provided by $other"
  if [[ -L $dst && $(readlink "$dst") == "$ours" ]]; then
    apply "remove duplicate $dst" sudo rm -f -- "$dst"
  fi
}

_cleanup_build() {
  find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name "$TMP_PREFIX.*" \
    -user "$USER" -exec rm -rf -- {} + 2>/dev/null || true
}

_build_plugin() {
  local ver=${PW_VER_DEB%%-*} build src target
  target=spa/plugins/bluez5/libspa-codec-bluez5-aac.so
  build=$(mktemp -d -p "${TMPDIR:-/tmp}" "$TMP_PREFIX.XXXXXX")
  cd "$build"
  if ! apt-get source "pipewire=$PW_VER_DEB"; then
    echo "Debian source $PW_VER_DEB unavailable; using upstream $ver"
    curl -fsSL "$PW_TARBALLS/$ver/pipewire-$ver.tar.gz" | tar xz
  fi
  src="$build/pipewire-$ver"
  [[ -d $src ]] || { echo "source dir $src not found"; return 1; }
  meson setup "$src/build" "$src" \
    -Dbluez5=enabled -Dbluez5-codec-aac=enabled \
    -Dtests=disabled -Dexamples=disabled -Ddocs=disabled -Dman=disabled
  ninja -C "$src/build" "$target"
  sudo install -m 644 "$src/build/$target" "$PLUGIN"
  mkdir -p "$(dirname "$STAMP")"
  echo "$PW_VER_DEB" >"$STAMP"
}

build_plugin() {
  step "AAC codec plugin"
  if [[ -f $PLUGIN && -f $STAMP && $(<"$STAMP") == "$PW_VER_DEB" ]]; then
    skip "plugin already built for PipeWire $PW_VER_DEB"
    return 0
  fi
  apt_update
  apt_ensure "${BUILD_DEPS[@]}"
  apply "apt: build dependencies of pipewire" \
    sudo DEBIAN_FRONTEND=noninteractive apt-get build-dep -y pipewire
  # After build-dep: pipewire has Build-Conflicts: libfdk-aac-dev, so
  # build-dep removes it.
  apply "apt: install libfdk-aac-dev" \
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libfdk-aac-dev
  on_exit _cleanup_build
  apply "build + install $(basename "$PLUGIN") for PipeWire $PW_VER_DEB" \
    _build_plugin
  _cleanup_build
  RESTART_NEEDED=1
}

bluez_cards() {
  pactl list cards short 2>/dev/null | awk '/bluez_card/ {print $2}'
}

card_info() { pactl list cards | sed -n "/Name: $1\$/,/^Card #/p"; }

# Profile names are not fixed; find the AAC one by its description.
aac_profile() {
  card_info "$1" | awk -F: '/\(A2DP Sink, codec AAC\)/ {
    gsub(/^[ \t]+/, "", $1); print $1; exit
  }'
}

_restart_audio() {
  systemctl --user restart pipewire pipewire-pulse wireplumber
  # Wait up to 20s for a Bluetooth card to (re)appear, then let profiles
  # settle.
  local _
  for _ in $(seq 20); do
    [[ -n $(bluez_cards) ]] && break
    sleep 1
  done
  sleep 2
}

restart_and_select() {
  step "Audio services"
  if ((RESTART_NEEDED)); then
    apply "restart pipewire, pipewire-pulse, wireplumber" _restart_audio
  else
    skip "nothing changed; no restart needed"
  fi

  local card prof active
  for card in $(bluez_cards); do
    prof=$(aac_profile "$card")
    active=$(card_info "$card" | awk '/Active Profile:/ {print $3; exit}')
    if [[ -z $prof ]]; then
      continue
    elif [[ $active == "$prof" ]]; then
      skip "$card already on $prof (AAC)"
    else
      apply "$card: $active → $prof (AAC)" \
        pactl set-card-profile "$card" "$prof"
    fi
  done
}

fail() {
  error "$*"
  FAIL=1
}

# check CONDITION-CMD... -- ok/fail with the messages in OK_MSG / FAIL_MSG.
check() {
  if "$@"; then ok "$OK_MSG"; else fail "$FAIL_MSG"; fi
}

verify_plugin() {
  OK_MSG="plugin installed: $PLUGIN"
  FAIL_MSG="plugin missing: $PLUGIN"
  check test -f "$PLUGIN"

  local stamp=''
  [[ -f $STAMP ]] && stamp=$(<"$STAMP")
  OK_MSG="plugin built for installed PipeWire $PW_VER_DEB"
  FAIL_MSG="build stamp does not match PipeWire $PW_VER_DEB;"
  FAIL_MSG+=" remove $STAMP and re-run"
  check test "$stamp" = "$PW_VER_DEB"

  [[ -f $PLUGIN ]] || return 0
  local libs
  libs=$(ldd "$PLUGIN")
  if grep -q 'not found' <<<"$libs"; then
    fail "plugin has unresolved libraries:" \
      "$(grep 'not found' <<<"$libs" | xargs)"
  elif grep -q libfdk-aac <<<"$libs"; then
    ok "plugin links libfdk-aac"
  else
    fail "plugin does not link libfdk-aac"
  fi
}

verify_services() {
  local svc
  for svc in pipewire pipewire-pulse wireplumber; do
    OK_MSG="$svc running"
    FAIL_MSG="$svc not running"
    check systemctl --user is-active -q "$svc"
  done

  local hfp
  hfp=$(wpctl settings bluetooth.autoswitch-to-headset-profile \
    2>/dev/null || true)
  OK_MSG="HFP auto-switch disabled"
  FAIL_MSG="bluetooth.autoswitch-to-headset-profile is not false"
  FAIL_MSG+=" (config not loaded?)"
  check grep -qi false <<<"$hfp"
}

verify_resampler() {
  local name got
  for name in pipewire-pulse.conf client.conf; do
    got=$(pw-config -n "$name" merge stream.properties 2>/dev/null |
      grep -o '"resample.quality": *[0-9]*' | grep -o '[0-9]*$' || true)
    if [[ $got == "$RESAMPLE_QUALITY" ]]; then
      ok "$name: resample.quality = $got"
    else
      fail "$name: resample.quality is '${got:-unset}'," \
        "expected $RESAMPLE_QUALITY"
    fi
  done

  # Streams playing now. PulseAudio apps reconnect after a restart and get
  # the new value; native PipeWire apps keep the old one until restarted.
  local app q
  while IFS=$'\t' read -r app q; do
    [[ -n $app ]] || continue
    if [[ $q == "$RESAMPLE_QUALITY" ]]; then
      ok "stream '$app': resample.quality = $q"
    else
      warn "stream '$app': resample.quality = $q" \
        "(restart the app to apply $RESAMPLE_QUALITY)"
    fi
  done < <(pw-dump 2>/dev/null | python3 -I -c "$PY_STREAMS")
}

# What was negotiated: the A2DP transport config from BlueZ.
# AAC config bytes:
#   [object type][freq hi][freq lo|channels][VBR|br hi][br mid][br lo]
verify_transport() { # mac
  local mac=$1 tr tcodec rate ch br line
  local -a cfg b
  tr=$(busctl tree org.bluez --list 2>/dev/null |
    grep -m1 "/dev_${mac}/sep[0-9]*/fd[0-9]*\$" || true)
  if [[ -z $tr ]]; then
    fail "no active BlueZ A2DP transport for $mac"
    return 0
  fi
  tcodec=$(busctl get-property org.bluez "$tr" \
    org.bluez.MediaTransport1 Codec | awk '{print $2}')
  read -r -a cfg <<<"$(busctl get-property org.bluez "$tr" \
    org.bluez.MediaTransport1 Configuration)"
  if [[ $tcodec != 2 || ${#cfg[@]} -lt 8 ]]; then
    fail "BlueZ transport codec is $tcodec (2 = AAC), config: ${cfg[*]}"
    return 0
  fi
  b=("${cfg[@]:2}")
  rate='?'
  ((b[2] & 0x80)) && rate=48000
  ((b[1] & 0x01)) && rate=44100
  ch='?'
  ((b[2] & 0x04)) && ch=2
  ((b[2] & 0x08)) && ch=1
  br=$((((b[3] & 0x7f) << 16) | (b[4] << 8) | b[5]))
  line="AAC ${rate} Hz, ${ch}ch, ${br} bps"
  if ((br >= AAC_MIN_BITRATE)) && [[ $ch == 2 ]]; then
    ok "negotiated: $line"
  else
    fail "negotiated: $line (expected stereo, >= $AAC_MIN_BITRATE bps)"
  fi
}

verify_sink() { # card mac
  local sink codec
  sink=$(pactl list sinks short |
    awk -v c="$2" '$2 ~ c {print $2; exit}')
  if [[ -z $sink ]]; then
    fail "no sink for $1"
    return 0
  fi
  codec=$(pactl list sinks | sed -n "/Name: $sink/,/^Sink #/p" |
    grep -m1 'api.bluez5.codec' | cut -d'"' -f2)
  if [[ $codec == aac ]]; then
    ok "sink $sink codec: aac"
  else
    fail "sink $sink codec is '$codec', expected aac"
  fi
}

verify_devices() {
  step "Verify: connected headphones"
  local cards
  cards=$(bluez_cards)
  if [[ -z $cards ]]; then
    warn "no Bluetooth audio device connected;" \
      "connect the AirPods Max 2 and re-run to verify the codec"
    return 0
  fi

  local card cinfo desc prof active mode
  for card in $cards; do
    cinfo=$(card_info "$card")
    desc=$(grep -m1 'device.description' <<<"$cinfo" | cut -d'"' -f2)
    info "$desc ($card)"

    prof=$(aac_profile "$card")
    if [[ -n $prof ]]; then
      ok "AAC profile offered: $prof"
    else
      fail "AAC profile not offered" \
        "(plugin not loaded, or device lacks AAC)"
    fi

    if grep -q 'codec SBC-XQ)' <<<"$cinfo"; then
      fail "SBC-XQ still offered (config not applied)"
    else
      ok "SBC-XQ disabled"
    fi

    active=$(grep -m1 'Active Profile:' <<<"$cinfo" | awk '{print $3}')
    if [[ -n $prof && $active == "$prof" ]]; then
      ok "active profile: $active (AAC)"
    else
      fail "active profile is '$active'," \
        "expected ${prof:-the AAC profile}"
    fi

    mode=$(pw-dump 2>/dev/null | python3 -I -c "$PY_BITRATEMODE" "$card")
    if [[ $mode == "$AAC_BITRATEMODE" ]]; then
      ok "AAC bitrate mode: $mode"
    else
      fail "AAC bitrate mode is '${mode:-unknown}'," \
        "expected $AAC_BITRATEMODE"
    fi

    verify_transport "${card#bluez_card.}"
    verify_sink "$card" "${card#bluez_card.}"
  done
}

verify_all() {
  step "Verify: plugin and config"
  verify_plugin
  verify_services
  verify_resampler
  verify_devices
  ((FAIL == 0)) || die "some checks failed (see the red lines above)"
}

main() {
  lib_init "AirPods Max 2: AAC over Bluetooth on PipeWire" "$@"
  no_extra_args
  require_user
  need_sudo
  require_cmd pactl pw-dump pw-config wpctl busctl python3 curl

  read_expected
  locate_plugin
  link_configs
  build_plugin
  restart_and_select

  if ((DRY_RUN)); then
    step "Verify"
    skip "verification skipped in dry run"
    return 0
  fi
  verify_all
}

main "$@"
