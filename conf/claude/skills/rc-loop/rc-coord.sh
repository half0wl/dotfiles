#!/usr/bin/env bash
# rc-coord.sh — cross-session coordination for rc-loop.
#
# File claims, session heartbeats, and an exclusive branch lock, so multiple
# Claude sessions can share one branch without racing. State lives outside
# the repo in ~/.claude/rc-loop/locks/<repo-key>/<branch-slug>/ :
#   <sid>.claim   ts=, stage=, files: — one claim per session
#   <sid>.hb      heartbeat; freshness (mtime) is the liveness signal
#   <sid>.hbpid   pid of the heartbeat loop
#   branch.lock   exclusive lock for whole-branch stages (refactor/review)
#
# Exit codes: 0 = ok/clear, 3 = contested/waiting/held, 1 = usage error.
set -euo pipefail

HB_INTERVAL=30   # seconds between heartbeat touches
HB_MAX_HOURS=6   # heartbeat self-terminates after this, even if orphaned
STALE_SECS=180   # heartbeat older than this => session presumed dead
POLL_SECS=10     # cadence inside wait loops

die() { echo "rc-coord: $*" >&2; exit 1; }
now() { date +%s; }
mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }

repo_key() {
  local common base h
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || die "not a git repo"
  base=$(basename "$(dirname "$common")")
  h=$(printf %s "$common" | shasum | cut -c1-8)
  printf '%s-%s' "$base" "$h"
}

branch_slug() {
  local b
  b=$(git branch --show-current)                       # empty when detached
  [ -n "$b" ] || b=$(git rev-parse --short HEAD 2>/dev/null) \
    || die "cannot determine branch"
  printf %s "$b" | tr '/' '-'
}

claim_field() {
  [ -f "$LD/$1.claim" ] || return 0
  sed -n "s/^$2=//p" "$LD/$1.claim" | head -1
}
claim_files() {
  [ -f "$LD/$1.claim" ] || return 0
  sed -n '/^files:/,$p' "$LD/$1.claim" | tail -n +2
}

is_live() {
  local hb="$LD/$1.hb"
  [ -f "$hb" ] && [ $(( $(now) - $(mtime "$hb") )) -lt "$STALE_SECS" ]
}

other_sids() {
  local me="$1" f sid
  for f in "$LD"/*.claim; do
    [ -e "$f" ] || continue
    sid=$(basename "$f" .claim)
    [ "$sid" = "$me" ] || echo "$sid"
  done
}

branch_holder() { cut -d' ' -f1 "$LD/branch.lock" 2>/dev/null || true; }

# Walk up from this shell to the claude CLI process, so the heartbeat can
# die with the session instead of surviving as an orphan.
find_claude_pid() {
  local pid=$$ cmd
  while [ "$pid" -gt 1 ]; do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null) || return 1
    case "$cmd" in *claude*) echo "$pid"; return 0 ;; esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
    [ -n "$pid" ] || return 1
  done
  return 1
}

cmd_claim() { # <sid> <file>... : create/extend claim, then report overlaps
  local sid="$1"; shift
  [ $# -gt 0 ] || die "claim: no files given"
  local ts stage
  ts=$(claim_field "$sid" ts); [ -n "$ts" ] || ts=$(now)
  stage=$(claim_field "$sid" stage); [ -n "$stage" ] || stage=implement
  { echo "ts=$ts"; echo "stage=$stage"; echo "files:"
    { claim_files "$sid"; printf '%s\n' "$@"; } | sort -u
  } >| "$LD/$sid.claim.tmp"
  mv "$LD/$sid.claim.tmp" "$LD/$sid.claim"
  touch "$LD/$sid.hb"
  cmd_overlaps "$sid"
}

cmd_overlaps() { # <sid> : exit 0 = clear, 3 = contested (winner printed)
  local me="$1" other contested rc=0 mts ots winner
  local mine; mine=$(claim_files "$me" | sort -u)
  [ -n "$mine" ] || die "overlaps: no claim for $me"
  for other in $(other_sids "$me"); do
    is_live "$other" || continue
    [ "$(claim_field "$other" stage)" = "implement" ] || continue
    contested=$(comm -12 <(printf '%s\n' "$mine") <(claim_files "$other" | sort -u))
    [ -n "$contested" ] || continue
    rc=3
    mts=$(claim_field "$me" ts); ots=$(claim_field "$other" ts)
    if [ "$mts" -lt "$ots" ] || { [ "$mts" -eq "$ots" ] && [ "$me" \< "$other" ]; }; then
      winner=$me
    else
      winner=$other
    fi
    echo "CONTESTED with $other (winner: $winner):"
    echo "$contested" | sed 's/^/  /'
  done
  [ "$rc" -eq 0 ] && echo "no overlaps"
  return "$rc"
}

cmd_hb_start() { # <sid> : background heartbeat tied to the claude process
  local sid="$1" cpid
  local hb="$LD/$sid.hb" pidf="$LD/$sid.hbpid"
  if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then
    echo "heartbeat already running (pid $(cat "$pidf"))"; return 0
  fi
  cpid=$(find_claude_pid || true)
  touch "$hb"
  nohup /usr/bin/env bash -c '
    hb="$1"; cpid="$2"; interval="$3"; deadline=$(( $(date +%s) + '"$HB_MAX_HOURS"'*3600 ))
    while :; do
      if [ -n "$cpid" ] && ! kill -0 "$cpid" 2>/dev/null; then break; fi
      [ "$(date +%s)" -gt "$deadline" ] && break
      touch "$hb"
      sleep "$interval"
    done
  ' hbloop "$hb" "$cpid" "$HB_INTERVAL" >/dev/null 2>&1 &
  echo "$!" >| "$pidf"
  echo "heartbeat started for $sid (claude pid: ${cpid:-not found — capped at ${HB_MAX_HOURS}h}, hb pid: $(cat "$pidf"))"
}

cmd_stage() { # <sid> <stage>
  local sid="$1" st="$2"
  local f="$LD/$sid.claim"
  [ -f "$f" ] || die "stage: no claim for $sid"
  sed -i '' "s/^stage=.*/stage=$st/" "$f"
  echo "$sid stage=$st"
}

cmd_wait_implement() { # <sid> [timeout] : until no other live implement claim
  local me="$1" timeout="${2:-240}" start busy o
  start=$(now)
  while :; do
    cmd_break_stale >/dev/null
    busy=""
    for o in $(other_sids "$me"); do
      if is_live "$o" && [ "$(claim_field "$o" stage)" = "implement" ]; then
        busy="$busy $o"
      fi
    done
    [ -z "$busy" ] && { echo "clear: no live implement claims besides $me"; return 0; }
    [ $(( $(now) - start )) -ge "$timeout" ] && { echo "still waiting on:$busy"; return 3; }
    sleep "$POLL_SECS"
  done
}

cmd_lock_branch() { # <sid> : atomic acquire; 3 = held by someone else
  local sid="$1" lk="$LD/branch.lock" holder
  cmd_break_stale >/dev/null
  if ( set -o noclobber; echo "$sid $(now)" > "$lk" ) 2>/dev/null; then
    echo "branch lock acquired by $sid"; return 0
  fi
  holder=$(branch_holder)
  [ "$holder" = "$sid" ] && { echo "branch lock already held by $sid"; return 0; }
  echo "branch lock held by ${holder:-unknown}"; return 3
}

cmd_wait_branch_free() { # <sid> [timeout] : until free, stale-broken, or ours
  local sid="$1" timeout="${2:-240}" start holder
  start=$(now)
  while :; do
    cmd_break_stale >/dev/null
    holder=$(branch_holder)
    if [ -z "$holder" ] || [ "$holder" = "$sid" ]; then
      echo "branch free for $sid"; return 0
    fi
    [ $(( $(now) - start )) -ge "$timeout" ] && { echo "branch still locked by $holder"; return 3; }
    sleep "$POLL_SECS"
  done
}

cmd_unlock_branch() { # <sid>
  local sid="$1" lk="$LD/branch.lock"
  [ -f "$lk" ] || { echo "branch lock already free"; return 0; }
  [ "$(branch_holder)" = "$sid" ] || die "unlock-branch: lock not held by $sid"
  rm -f "$lk"
  echo "branch lock released by $sid"
}

cmd_break_stale() { # remove claims/locks whose heartbeat died
  local f sid holder
  for f in "$LD"/*.claim; do
    [ -e "$f" ] || continue
    sid=$(basename "$f" .claim)
    if ! is_live "$sid"; then
      echo "breaking stale claim: $sid (heartbeat older than ${STALE_SECS}s)"
      rm -f "$f" "$LD/$sid.hb" "$LD/$sid.hbpid"
    fi
  done
  holder=$(branch_holder)
  if [ -n "$holder" ] && ! is_live "$holder"; then
    echo "breaking stale branch lock (holder $holder is dead)"
    rm -f "$LD/branch.lock"
  fi
  return 0
}

cmd_release() { # <sid> : stop heartbeat, drop claim, free branch lock if ours
  local sid="$1"
  local pidf="$LD/$sid.hbpid"
  [ -f "$pidf" ] && kill "$(cat "$pidf")" 2>/dev/null || true
  [ "$(branch_holder)" = "$sid" ] && rm -f "$LD/branch.lock"
  rm -f "$LD/$sid.claim" "$LD/$sid.hb" "$pidf"
  echo "released $sid"
}

cmd_status() {
  echo "lockdir: $LD"
  local f sid age any=0
  for f in "$LD"/*.claim; do
    [ -e "$f" ] || continue
    any=1
    sid=$(basename "$f" .claim)
    age=$(( $(now) - $(mtime "$LD/$sid.hb") ))
    echo "- $sid stage=$(claim_field "$sid" stage) ts=$(claim_field "$sid" ts) hb_age=${age}s live=$(is_live "$sid" && echo yes || echo NO)"
    claim_files "$sid" | sed 's/^/    /'
  done
  [ "$any" -eq 0 ] && echo "no claims"
  if [ -f "$LD/branch.lock" ]; then
    echo "branch.lock: held by $(cat "$LD/branch.lock")"
  else
    echo "branch.lock: free"
  fi
}

usage() {
  sed -n 's/^cmd_\([a-z_]*\)() { # /  \1 /p' "$0" | tr '_' '-'
  exit 1
}

[ $# -ge 1 ] || usage
CMD=$1; shift
LD="$HOME/.claude/rc-loop/locks/$(repo_key)/$(branch_slug)"
mkdir -p "$LD"

case "$CMD" in
  claim)            cmd_claim "$@" ;;
  overlaps)         cmd_overlaps "$@" ;;
  hb-start)         cmd_hb_start "$@" ;;
  stage)            cmd_stage "$@" ;;
  wait-implement)   cmd_wait_implement "$@" ;;
  lock-branch)      cmd_lock_branch "$@" ;;
  wait-branch-free) cmd_wait_branch_free "$@" ;;
  unlock-branch)    cmd_unlock_branch "$@" ;;
  break-stale)      cmd_break_stale ;;
  release)          cmd_release "$@" ;;
  status)           cmd_status ;;
  *)                usage ;;
esac
