# shellcheck shell=bash
# shellcheck disable=SC2034  # colors/flags are used by the sourcing scripts
# https://github.com/half0wl/dotfiles
#
# _lib.sh
#
# Shared output, prompts and idempotent helpers for the setup scripts, so
# they all look and behave the same. Source it at the top of every script:
#
#   source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"
#
# then start main() with `lib_init "<short title>" "$@"`.
#
# Every script accepts:
#   -n, --dry-run   show what would change, change nothing
#   -y, --yes       answer yes to every confirmation prompt
#   -h, --help      print the script's header comment
#
# Output (one marker per line, same everywhere; arguments are joined with
# spaces, so long messages can be split across lines):
#   step "Title"        section header
#   info "msg"          [ i ] neutral information
#   ok "msg"            [ ✔ ] a check passed
#   changed "msg"       [ + ] something was changed        (counted)
#   skip "msg"          [ - ] already in place, no-op      (counted)
#   would "msg"         [ ~ ] dry run: would change        (counted)
#   warn "msg"          [ ⚠ ] needs attention, not fatal   (counted)
#   error "msg"         [ ✘ ] failure (stderr)
#   die "msg"           error + exit 1
#   detail "msg"        indented, dimmed sub-line
#
# Running commands:
#   busy  "msg" cmd...  read-only work behind a spinner; runs in dry-run
#   apply "msg" cmd...  a change behind a spinner; skipped in dry-run
#   apply_tty "msg" cmd...
#                       a change that needs the terminal (passwords)
#   confirm "question" [Y|N]
#
#   Command output goes to a log file; on failure the last lines of the
#   log are printed in red and the script exits (set -e). Call busy/apply
#   as plain statements, never under `||`, `&&` or `if`: bash then ignores
#   `set -e` inside shell functions passed to them.
#
# Idempotent helpers (each checks first and reports skip/changed):
#   link_conf <conf-relative-src> <dst>   symlink dst -> conf/<src>
#   ensure_link <target> <dst>            symlink dst -> target
#   apt_ensure pkg...                     install missing apt packages
#   apt_update                            refresh package lists
#   deb_ensure <pkg> <url>                install a .deb if missing
#   systemd_enable <unit> [--now]         enable (and start) a unit
#   kconf_set [--notify] [--default V] <file> <group> <key> <value>
#   kglobal_set <shortcut-id> <keys|none> <label>     (see below)
#
# Flags set by helpers so scripts can react to changes:
#   LINK_CHANGED=1   a link was created or changed
#   KCONF_CHANGED=1  a KDE config key was written
#
# Style: no line in this file or the scripts is longer than 78 characters.

[[ -n ${_LIB_SH_LOADED:-} ]] && return 0
_LIB_SH_LOADED=1

# ---------------------------------------------------------------------------
# Paths and state
# ---------------------------------------------------------------------------

LIB_DIR="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
LIB_DIR="$(cd -- "$LIB_DIR" && pwd -P)"
# The scripts live in sh/; conf/ sits next to it.
REPO_DIR="$(dirname -- "$LIB_DIR")"
CONF_DIR="$REPO_DIR/conf"
SCRIPT_PATH="$(readlink -f -- "$0")"
SCRIPT_NAME="$(basename -- "$SCRIPT_PATH")"

DRY_RUN=0
ASSUME_YES=0
ARGS=() # arguments lib_init did not recognise, for the script to handle

LINK_CHANGED=0
KCONF_CHANGED=0

_N_CHANGED=0
_N_SKIPPED=0
_N_WARN=0
_SPIN_PID=""
_SUDO_PID=""
_EXIT_HOOKS=()
_QUIET_EXIT=0

# ---------------------------------------------------------------------------
# Colors (off when stdout is not a terminal, or NO_COLOR is set)
# ---------------------------------------------------------------------------

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  C_RED=$'\e[31m'
  C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m'
  C_BLUE=$'\e[34m'
  C_PURPLE=$'\e[35m'
  C_CYAN=$'\e[36m'
  C_GREY=$'\e[90m'
  C_BRED=$'\e[91m'
  C_BGREEN=$'\e[92m'
  C_BYELLOW=$'\e[93m'
  C_BPURPLE=$'\e[95m'
  C_BOLD=$'\e[1m'
  C_DIM=$'\e[2m'
  C_ITALIC=$'\e[3m'
  C_UNDERLINE=$'\e[4m'
  C_OFF=$'\e[0m'
  _TTY=1
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_PURPLE='' C_CYAN=''
  C_GREY='' C_BRED='' C_BGREEN='' C_BYELLOW='' C_BPURPLE=''
  C_BOLD='' C_DIM='' C_ITALIC='' C_UNDERLINE='' C_OFF=''
  _TTY=0
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

_line() { # color marker message...
  local color=$1 mark=$2
  shift 2
  _spin_stop
  printf '%s%s%s %s\n' "$color" "$mark" "$C_OFF" "$*"
}

step() {
  _spin_stop
  printf '\n%s==>%s %s%s%s\n' \
    "$C_BPURPLE$C_BOLD" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"
}

info() { _line "$C_CYAN" '[ i ]' "$*"; }
ok() { _line "$C_GREEN" '[ ✔ ]' "$*"; }
error() { _line "$C_BRED$C_BOLD" '[ ✘ ]' "$C_RED$*$C_OFF" >&2; }
die() { error "$*"; exit 1; }

changed() {
  _N_CHANGED=$((_N_CHANGED + 1))
  _line "$C_BGREEN$C_BOLD" '[ + ]' "$*"
}

skip() {
  _N_SKIPPED=$((_N_SKIPPED + 1))
  _spin_stop
  printf '%s[ - ] %s%s\n' "$C_GREY" "$*" "$C_OFF"
}

would() {
  _N_CHANGED=$((_N_CHANGED + 1))
  _line "$C_BLUE" '[ ~ ]' "${C_DIM}would:${C_OFF} $*"
}

warn() {
  _N_WARN=$((_N_WARN + 1))
  _line "$C_YELLOW" '[ ⚠ ]' "$C_YELLOW$*$C_OFF"
}

detail() {
  _spin_stop
  printf '      %s%s%s\n' "$C_GREY" "$*" "$C_OFF"
}

# Shorten $HOME to ~ for display.
pretty() { printf '%s' "${1/#$HOME/\~}"; }

# ---------------------------------------------------------------------------
# Spinner
# ---------------------------------------------------------------------------

_spin_start() { # message
  ((_TTY)) || return 0
  _spin_stop
  local msg=$1
  (
    trap 'exit 0' TERM
    local frames=('⠋ ○' '⠙○ ' ' ⠹ ' '○⠸ ' ' ⠼○' ' ⠴ ' ' ⠦ ' '○⠧ ' ' ⠇○' ' ⠏ ')
    local i=0 start=$SECONDS elapsed frame
    while :; do
      elapsed=$((SECONDS - start))
      if ((elapsed >= 2)); then
        elapsed=" ${C_GREY}${elapsed}s${C_OFF}"
      else
        elapsed=''
      fi
      frame=${frames[i++ % ${#frames[@]}]}
      printf '\r\e[2K%s[%s]%s %s%s' \
        "$C_BPURPLE" "$frame" "$C_OFF" "$msg" "$elapsed"
      sleep 0.1
    done
  ) &
  _SPIN_PID=$!
  printf '\e[?25l'
}

_spin_stop() {
  [[ -n $_SPIN_PID ]] || return 0
  kill "$_SPIN_PID" 2>/dev/null || true
  wait "$_SPIN_PID" 2>/dev/null || true
  _SPIN_PID=""
  printf '\r\e[2K\e[?25h'
}

# ---------------------------------------------------------------------------
# Running commands
# ---------------------------------------------------------------------------

# Run "$@" behind a spinner with its output in a log file; the exit code is
# left in _RUN_RC. The command runs as a background job, and _run_logged
# itself must be called as a plain statement (never under `||`, `&&` or
# `if`): bash ignores `set -e` for everything run inside such a context,
# including shell functions passed in here, which would then carry on
# after a failure.
_RUN_RC=0
_run_logged() { # message cmd...
  local msg=$1 log rc=0 pid
  shift
  log="$(mktemp -t "${SCRIPT_NAME%.sh}.XXXXXX.log")"
  _spin_start "$msg"
  "$@" >"$log" 2>&1 </dev/null &
  pid=$!
  wait "$pid" || rc=$?
  _spin_stop
  _RUN_RC=$rc
  if ((rc)); then
    error "$msg (exit $rc)"
    tail -n 20 "$log" | sed "s/^/      ${C_RED}│${C_OFF} /" >&2
    detail "full log: $log" >&2
    return 0
  fi
  rm -f -- "$log"
}

# busy MESSAGE CMD... -- read-only work (checks, downloads to temp). Runs
# in dry-run mode too. Call it as a plain statement (see _run_logged).
busy() {
  local msg=$1
  shift
  _run_logged "$msg" "$@"
  ((_RUN_RC == 0)) || return "$_RUN_RC"
  ok "$msg"
}

# apply MESSAGE CMD... -- a change. Only printed in dry-run mode. Call it
# as a plain statement (see _run_logged).
apply() {
  local msg=$1
  shift
  if ((DRY_RUN)); then
    would "$msg"
    return 0
  fi
  _run_logged "$msg" "$@"
  ((_RUN_RC == 0)) || return "$_RUN_RC"
  changed "$msg"
}

# apply_tty MESSAGE CMD... -- a change that talks to the user
# (passphrases, interactive tools). No spinner; output goes straight to
# the terminal.
apply_tty() {
  local msg=$1 rc=0
  shift
  if ((DRY_RUN)); then
    would "$msg"
    return 0
  fi
  _line "$C_BLUE" '[ » ]' "$msg"
  "$@" || rc=$?
  if ((rc)); then
    error "$msg (exit $rc)"
    return "$rc"
  fi
  changed "$msg"
}

# confirm QUESTION [Y|N] -- default N. --yes answers yes; dry-run assumes
# yes (the change itself is then only printed); no terminal takes the
# default.
confirm() {
  local question=$1 def=${2:-N} hint ans why
  [[ $def == Y ]] && hint='[Y/n]' || hint='[y/N]'
  _spin_stop
  if ((ASSUME_YES || DRY_RUN)); then
    ((DRY_RUN)) && why='dry run' || why='--yes'
    printf '%s[ ? ]%s %s %s %s\n' "$C_BLUE" "$C_OFF" "$question" "$hint" \
      "${C_GREY}yes ($why)${C_OFF}"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    printf '%s[ ? ]%s %s %s %s\n' "$C_BLUE" "$C_OFF" "$question" "$hint" \
      "${C_GREY}${def} (no terminal)${C_OFF}"
    [[ $def == Y ]]
    return
  fi
  read -r -p "$(printf '%s[ ? ]%s %s %s ' \
    "$C_BLUE" "$C_OFF" "$question" "$hint")" ans || ans=''
  [[ ${ans:-$def} == [yY]* ]]
}

# ---------------------------------------------------------------------------
# Startup, exit and summary
# ---------------------------------------------------------------------------

usage() {
  _QUIET_EXIT=1
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
    "$SCRIPT_PATH"
  exit 0
}

# lib_init TITLE "$@" -- parse the common flags, print the banner.
lib_init() {
  local title=$1
  shift
  while (($#)); do
    case $1 in
      -n | --dry-run) DRY_RUN=1 ;;
      -y | --yes) ASSUME_YES=1 ;;
      -h | --help) usage ;;
      *) ARGS+=("$1") ;;
    esac
    shift
  done
  printf '%s━━ %s%s %s%s%s\n' "$C_BPURPLE" "$C_OFF$C_BOLD" "$SCRIPT_NAME" \
    "$C_OFF$C_GREY" "$title" "$C_OFF"
  if ((DRY_RUN)); then
    printf '%sdry run: nothing will be changed%s\n' "$C_BLUE" "$C_OFF"
  fi
}

# Die on any argument lib_init did not recognise.
no_extra_args() {
  ((${#ARGS[@]} == 0)) || die "unknown argument: ${ARGS[0]} (try --help)"
}

# on_exit CMD -- run CMD (eval'd) when the script exits, before the summary.
on_exit() { _EXIT_HOOKS+=("$1"); }

_lib_exit() {
  local rc=$? hook
  _spin_stop
  [[ -n $_SUDO_PID ]] && kill "$_SUDO_PID" 2>/dev/null
  for hook in "${_EXIT_HOOKS[@]}"; do
    eval "$hook" || true
  done
  ((_QUIET_EXIT)) && exit "$rc"

  # if-statements only: a failing `a && b` as the last command would trip
  # `set -e` inside this trap.
  local counts verb=changed plural=''
  if ((DRY_RUN)); then verb='would change'; fi
  if ((_N_WARN > 1)); then plural=s; fi
  counts="$_N_CHANGED $verb · $_N_SKIPPED unchanged"
  if ((_N_WARN)); then
    counts+=" · ${C_YELLOW}$_N_WARN warning$plural${C_OFF}"
  fi
  echo
  if ((rc == 0)); then
    printf '%s━━ ✔ %s done%s  %s\n' \
      "$C_BGREEN$C_BOLD" "$SCRIPT_NAME" "$C_OFF" "$counts"
  else
    printf '%s━━ ✘ %s failed (exit %d)%s  %s\n' \
      "$C_BRED$C_BOLD" "$SCRIPT_NAME" "$rc" "$C_OFF" "$counts" >&2
  fi
  exit "$rc"
}

trap _lib_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------------------
# Requirements
# ---------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  local c
  for c; do have "$c" || die "'$c' not found"; done
}

require_user() {
  ((EUID != 0)) ||
    die "run as your normal user, not root (sudo is used where needed)"
}

require_debian13() {
  local codename
  codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
  [[ $codename == trixie ]] ||
    die "expected Debian 13 (trixie), found '${codename:-unknown}'"
}

require_plasma() {
  [[ ${XDG_CURRENT_DESKTOP:-} == *KDE* ]] ||
    die "needs a running Plasma session" \
      "(XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset})"
}

# need_sudo -- ask for the password once, up front, and keep the
# credentials fresh so later steps (behind spinners) never prompt.
need_sudo() {
  require_cmd sudo
  if ! sudo -n true 2>/dev/null; then
    [[ -t 0 ]] ||
      die "sudo needs your password, but there is no terminal to ask" \
        "on; run this from a terminal"
    info "sudo is needed for system changes"
    sudo -v || die "sudo authentication failed"
  fi
  (while kill -0 "$$" 2>/dev/null; do
    sudo -n true 2>/dev/null
    sleep 50
  done) &
  _SUDO_PID=$!
}

# ---------------------------------------------------------------------------
# Symlinks
# ---------------------------------------------------------------------------

# True if creating/replacing PATH needs root (nearest existing parent is
# not writable by us).
_needs_root() {
  local d
  d=$(dirname -- "$1")
  while [[ ! -e $d ]]; do d=$(dirname -- "$d"); done
  [[ ! -w $d ]]
}

_same_content() {
  if [[ -d $1 && -d $2 ]]; then
    diff -rq -- "$1" "$2" >/dev/null 2>&1
  elif [[ -f $1 && -f $2 ]]; then
    cmp -s -- "$1" "$2"
  else
    return 1
  fi
}

# Replaced files are kept here, under their original absolute path. Not
# next to the file: a stray backup in a .d directory (apt.conf.d,
# sources.list.d) makes apt complain on every run.
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-bak"
BACKUP_DIR+="/$(date +%Y%m%d-%H%M%S)"

_backup() { # path [sudo]
  local dst=$1 bak="$BACKUP_DIR$1"
  shift
  mkdir -p -- "$(dirname -- "$bak")"
  "$@" mv -- "$dst" "$bak"
  [[ $# -eq 0 ]] || sudo chown -Rh "$(id -u):$(id -g)" -- "$bak"
}

_LINK_NEW='mkdir -p -- "$(dirname -- "$2")" && ln -s -- "$1" "$2"'
_LINK_REPLACE='rm -rf -- "$2" && ln -s -- "$1" "$2"'

# ensure_link TARGET DST -- make DST a symlink to TARGET.
#   * already correct:        skip
#   * a link elsewhere:       repoint it
#   * a file/dir, identical:  replace it with the link
#   * a file/dir, different:  warn, move it to $BACKUP_DIR/<DST>, then link
ensure_link() {
  local target=$1 dst=$2 cur
  local -a sudo=()
  _needs_root "$dst" && sudo=(sudo)
  if [[ ! -e $target && ! -L $target ]]; then
    # In a dry run an earlier step may only "would" have created it.
    ((DRY_RUN)) || die "link target does not exist: $target"
    would "link $(pretty "$dst") → $(pretty "$target") (once it exists)"
    return 0
  fi

  local p_dst p_target
  p_dst=$(pretty "$dst")
  p_target=$(pretty "$target")

  if [[ -L $dst ]]; then
    cur=$(readlink -- "$dst")
    if [[ $cur == "$target" ]]; then
      skip "$p_dst already linked"
      return 0
    fi
    apply "relink $p_dst → $p_target (was $(pretty "$cur"))" \
      "${sudo[@]}" ln -sfn -- "$target" "$dst"
    LINK_CHANGED=1
    return 0
  fi

  if [[ -e $dst ]]; then
    if _same_content "$target" "$dst"; then
      apply "link $p_dst → $p_target (replaces identical copy)" \
        "${sudo[@]}" sh -c "$_LINK_REPLACE" _ "$target" "$dst"
      LINK_CHANGED=1
      return 0
    fi
    warn "$p_dst differs from $p_target; backing it up first"
    if [[ -f $dst && -f $target ]]; then
      diff -u --label "$p_target" --label "$p_dst" -- "$target" "$dst" \
        2>/dev/null | head -n 15 | sed 's/^/        /' || true
    fi
    apply "back up $p_dst → $(pretty "$BACKUP_DIR$dst")" \
      _backup "$dst" "${sudo[@]}"
  fi

  apply "link $p_dst → $p_target" \
    "${sudo[@]}" sh -c "$_LINK_NEW" _ "$target" "$dst"
  LINK_CHANGED=1
}

# link_conf SRC DST -- symlink DST to conf/SRC (SRC is relative to conf/).
link_conf() {
  [[ -e $CONF_DIR/$1 ]] || die "missing from conf/: $1"
  ensure_link "$CONF_DIR/$1" "$2"
}

# ---------------------------------------------------------------------------
# Packages and services
# ---------------------------------------------------------------------------

pkg_installed() {
  local status
  status=$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null || true)
  [[ $status == ii* ]]
}

# apt_ensure PKG... -- install whichever packages are missing.
apt_ensure() {
  local p
  local -a missing=()
  for p; do pkg_installed "$p" || missing+=("$p"); done
  if ((${#missing[@]} == 0)); then
    if (($# <= 4)); then
      skip "apt: $* already installed"
    else
      skip "apt: all $# packages already installed"
    fi
    return 0
  fi
  apply "apt: install ${missing[*]}" \
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

apt_update() {
  apply "apt: refresh package lists" sudo apt-get update
}

_install_deb_from_url() { # url
  local tmp
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/pkg.deb" "$1"
  chmod 755 "$tmp"
  chmod 644 "$tmp/pkg.deb"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/pkg.deb"
  rm -rf -- "$tmp"
}

# deb_ensure PKG URL -- install a .deb from URL unless PKG is installed.
deb_ensure() {
  if pkg_installed "$1"; then
    skip "$1 already installed"
    return 0
  fi
  apply "install $1 from $2" _install_deb_from_url "$2"
}

# systemd_enable UNIT [--now] -- enable (and with --now, start) a unit.
systemd_enable() {
  local unit=$1 now=${2:-}
  if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    skip "$unit already enabled"
  else
    apply "enable $unit" sudo systemctl enable "$unit"
  fi
  [[ $now == --now ]] || return 0
  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    skip "$unit already running"
  else
    apply "start $unit" sudo systemctl start "$unit"
  fi
}

# ---------------------------------------------------------------------------
# KDE config
# ---------------------------------------------------------------------------

# kconf_set [--notify] [--default VALUE] FILE GROUP KEY VALUE -- write one
# KDE config key if it differs. --default is what an unset key means, so
# an unset key that already behaves as VALUE is left alone. Nested groups
# are separated by "/": "Libinput/1133/45108/MX Master" is
# [Libinput][1133][45108][MX Master].
kconf_set() {
  local -a notify=() def=()
  while [[ $1 == --* ]]; do
    case $1 in
      --notify) notify=(--notify); shift ;;
      --default) def=(--default "$2"); shift 2 ;;
      *) die "kconf_set: unknown option $1" ;;
    esac
  done
  local file=$1 group=$2 key=$3 want=$4 cur part label
  local -a groups=() parts
  IFS='/' read -r -a parts <<<"$group"
  for part in "${parts[@]}"; do groups+=(--group "$part"); done
  label="$file [${group//\//][}] $key"

  cur=$(kreadconfig6 --file "$file" "${groups[@]}" --key "$key" \
    "${def[@]}")
  if [[ $cur == "$want" ]]; then
    skip "$label = $want"
    return 0
  fi
  apply "$label: ${cur:-(unset)} → $want" \
    kwriteconfig6 --file "$file" "${groups[@]}" --key "$key" \
    "${notify[@]}" "$want"
  KCONF_CHANGED=1
}

# ---------------------------------------------------------------------------
# KDE global shortcuts (kglobalaccel over D-Bus)
# ---------------------------------------------------------------------------
#
#   kglobal_id <component> <action>     action id, e.g. kwin "Overview"
#   kglobal_keys <id>                   active keys as Qt key codes
#   kglobal_set <id> <keys|none> <label>
#
# Shortcuts go through D-Bus, not kglobalshortcutsrc: kglobalacceld keeps
# them in memory and rewrites that file on exit, so edits get clobbered.
# An action id is [component, action, component-label, action-label];
# labels are translated, so ids are resolved at runtime. setShortcut()
# needs flags SetPresent(2) | NoAutoloading(4) = 6, or it re-reads the
# stored shortcut and ignores the new keys. On Plasma 6.3.6
# setShortcutKeys() and globalShortcutAvailable() crash kglobalacceld, so
# only the (deprecated) setShortcut/shortcut pair is used.

KGLOBAL_PROBLEMS=0 # shortcuts that did not stick

declare -A _QT_MODS=(
  [meta]=0x10000000 [super]=0x10000000 [win]=0x10000000
  [shift]=0x02000000
  [ctrl]=0x04000000 [control]=0x04000000
  [alt]=0x08000000 [option]=0x08000000
)

declare -A _QT_KEYS=(
  [up]=0x01000013 [down]=0x01000015 [left]=0x01000012 [right]=0x01000014
  [home]=0x01000010 [end]=0x01000011
  [pageup]=0x01000016 [pagedown]=0x01000017
  [tab]=0x01000001 [backtab]=0x01000002
  [return]=0x01000004 [enter]=0x01000005
  [escape]=0x01000000 [esc]=0x01000000
  [backspace]=0x01000003 [delete]=0x01000007 [insert]=0x01000006
  [space]=0x20
  [f1]=0x01000030 [f2]=0x01000031 [f3]=0x01000032 [f4]=0x01000033
  [f5]=0x01000034 [f6]=0x01000035 [f7]=0x01000036 [f8]=0x01000037
  [f9]=0x01000038 [f10]=0x01000039 [f11]=0x0100003a [f12]=0x0100003b
)

# qkey "Meta+Up" -- the Qt key code the D-Bus API speaks.
qkey() {
  local spec=$1 out=0 part lower
  local IFS=+
  for part in $spec; do
    lower=${part,,}
    if [[ -n ${_QT_MODS[$lower]:-} ]]; then
      out=$((out | _QT_MODS[$lower]))
    elif [[ -n ${_QT_KEYS[$lower]:-} ]]; then
      out=$((out | _QT_KEYS[$lower]))
    elif ((${#part} == 1)); then
      out=$((out | $(printf '%d' "'${part^^}")))
    else
      die "cannot parse key '$part' in '$spec'"
    fi
  done
  printf '%d\n' "$out"
}

_kga() { # method args...
  gdbus call --session --dest org.kde.kglobalaccel \
    --object-path /kglobalaccel --method "org.kde.KGlobalAccel.$1" \
    "${@:2}"
}

kglobal_id() { # component action
  local flat id re comp=${1//./\\.}
  flat=$(_kga allActionsForComponent "['$1']" | tr '\n' ' ')
  re="\['$comp',[[:space:]]*'$2'[[:space:]]*,[^]]*\]"
  id=$(grep -oE "$re" <<<"$flat" | head -n1 || true)
  [[ -n $id ]] ||
    die "shortcut '$1' / '$2' is not registered with kglobalaccel"
  printf '%s\n' "$id"
}

kglobal_keys() { # id
  local out
  out=$(_kga shortcut "$1")
  grep -oE '[0-9]+' <<<"$out" | paste -sd' ' - || true
}

kglobal_set() { # id keys|none label
  local id=$1 spec=$2 label=$3 desired='' current gv shown
  [[ $spec == none ]] || desired=$(qkey "$spec")
  shown=${spec/none/(unbound)}
  current=$(kglobal_keys "$id")
  if [[ $current == "$desired" ]]; then
    skip "$label: $shown"
    return 0
  fi
  if [[ -z $desired ]]; then gv='@ai []'; else gv="[$desired]"; fi
  apply "$label: $shown" _kga setShortcut "$id" "$gv" "uint32 6"
  ((DRY_RUN)) && return 0

  current=$(kglobal_keys "$id")
  if [[ $current != "$desired" ]]; then
    warn "$label did not stick (wanted '$spec', got" \
      "'${current:-empty}'); set it in System Settings > Shortcuts"
    KGLOBAL_PROBLEMS=$((KGLOBAL_PROBLEMS + 1))
  fi
}
