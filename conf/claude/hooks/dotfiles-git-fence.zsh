#!/bin/zsh
# PreToolUse hook (Bash): Claude never runs git, or gh/hub (which drive git),
# against ~/dotfiles. Ray does every git operation there himself.
#
# The sandbox already denies ~/dotfiles/.git to sandboxed commands. This hook
# covers what runs outside the sandbox (git push/fetch/pull and gh are exempt
# for credentials) and refuses the attempt up front with a clear reason.
#
# Refuses a Bash call when it invokes git/gh/hub AND touches ~/dotfiles: the
# working directory is inside it, the command names it, or a path in the
# command resolves into it (~/.claude/skills, for one, is a symlink into it).
#
# Input: the hook JSON on stdin. Output: a deny decision, or nothing to let
# the call through.

emulate -L zsh

input=$(cat)
lower_input=${(L)input}

# Cheap pre-filter: nothing to check unless git/gh/hub appears somewhere.
[[ $lower_input == *git* || $lower_input == *gh* || $lower_input == *hub* ]] || exit 0

field() {
  print -rn -- "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null
}

deny() {
  print -r -- '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Git operations in ~/dotfiles are off-limits to Claude (no git, gh or hub there). Ray runs them himself."}}'
  exit 0
}

dot=$HOME/dotfiles
dot=${dot:A}
dot=${(L)dot}

cmd=$(field tool_input.command)
if [[ -z $cmd ]]; then
  # Unreadable input: fail closed only when dotfiles is mentioned.
  [[ $lower_input == *dotfiles* ]] && deny
  exit 0
fi
cwd=$(field cwd)
[[ -n $cwd ]] || cwd=$PWD

# Does the command run git/gh/hub as a command word? Quotes and backslashes
# become spaces first so "git", 'gh' and \git still count.
words=${(L)cmd//[\"\'\\]/ }
[[ $words =~ '(^|[[:space:];&|(`/!])(git|gh|hub)([[:space:];&|)]|$)' ]] || exit 0

# Working directory inside ~/dotfiles.
here=${cwd:A}
here=${(L)here}
[[ $here == $dot || $here == $dot/* ]] && deny

# The command names dotfiles outright.
[[ $words == *dotfiles* ]] && deny

# A path in the command resolves into ~/dotfiles (symlinks, $HOME, ~).
for w in ${(z)cmd}; do
  w=${(Q)w}
  w=${w#*=}
  w=${w/#\$\{HOME\}/$HOME}
  w=${w/#\$HOME/$HOME}
  [[ $w == '~'* ]] && w=$HOME${w#\~}
  if [[ $w != /* ]]; then
    [[ $w == */* ]] || continue
    w=$cwd/$w
  fi
  r=${w:A}
  r=${(L)r}
  [[ $r == $dot || $r == $dot/* ]] && deny
done
exit 0
