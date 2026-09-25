#!/bin/zsh
# Stop hook: ping when a Claude turn ends and Ray is not looking at its pane.
#
# Claude Code has no native "turn finished" notification. It only pings for
# permission prompts (after 6s) and "waiting for input" (60s after a turn), so
# this fills the gap for Claude running inside tmux inside Ghostty.
#
# Hooks run detached with stdout captured, so there is no terminal to print
# to. The ping goes to the pane's own tty, which tmux reads as pane output:
#   - Ghostty focused on tmux, Claude pane in view: nothing.
#   - Ghostty focused on tmux, Claude pane out of view: BEL only. Ghostty
#     hides banners for its focused surface; tmux flags the window.
#   - Ghostty not focused: OSC 777 banner via tmux passthrough, plus BEL,
#     labelled with the session's topic, e.g. "Fix auth (pane 0.2)".
#
# Needs `allow-passthrough all` and `focus-events on` in ~/.tmux.conf.
# Always exits 0: a Stop hook that exits 2 makes Claude keep going.

emulate -L zsh

[[ -n $TMUX_PANE ]] || exit 0

pane() { tmux display -p -t "$TMUX_PANE" "$1" 2>/dev/null }

tty=$(pane '#{pane_tty}')
[[ -n $tty ]] || exit 0
session_id=$(pane '#{session_id}')
in_view=$(pane '#{&&:#{pane_active},#{window_active}}')
where=$(pane '#{window_index}.#{pane_index}')

# Claude titles its pane "<status glyph> <topic>", which names the session
# better than tmux coordinates when several Claudes share one window. Pane
# titles are program-controlled: strip control bytes so nothing can break out
# of the escape sequence below.
title=$(pane '#{pane_title}')
title=${title//[[:cntrl:]]/}
[[ $title == [^[:alnum:]]*' '* ]] && title=${title#* }
if [[ -n $title ]]; then
  label="$title (pane $where)"
else
  label="Turn done in pane $where"
fi

esc=$'\e'
bel=$'\a'

client_flags=$(tmux list-clients -t "$session_id" -F '#{client_flags}' 2>/dev/null)
if [[ $client_flags == *focused* ]]; then
  [[ $in_view == 1 ]] && exit 0
  print -rn -- "$bel" > $tty
  exit 0
fi

osc="${esc}]777;notify;Claude Code;${label}${bel}"
# tmux passthrough: wrap in DCS and double every ESC inside it.
wrapped="${esc}Ptmux;${osc//$esc/$esc$esc}${esc}\\"
print -rn -- "$wrapped$bel" > $tty
exit 0
