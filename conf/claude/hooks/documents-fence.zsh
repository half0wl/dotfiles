#!/bin/zsh
# PreToolUse hook: keeps Claude's file tools (Read, Grep, Glob, Edit, Write,
# NotebookEdit) out of ~/Documents, except the Obsidian vault
# ~/Documents/Yggdrasil.
#
# Permission rules can't express this without naming every other folder: an
# allow never overrides a deny, and a `!` carve-out can't reach a ~-anchored
# rule. Bash is fenced separately by the sandbox (denyRead ~/, with the vault
# re-opened).
#
# Input: the hook JSON on stdin. Output: a deny decision, or nothing to let
# the call through.

emulate -L zsh

input=$(cat)

field() {
  print -rn -- "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null
}

deny() {
  print -r -- '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"~/Documents is off-limits to Claude except ~/Documents/Yggdrasil. Read or search a narrower path."}}'
  exit 0
}

# APFS is case-insensitive, so compare resolved, lowercased paths.
docs=$HOME/Documents
docs=${docs:A}
docs=${(L)docs}
vault=$HOME/Documents/Yggdrasil
vault=${vault:A}
vault=${(L)vault}

tool=$(field tool_name)
if [[ -z $tool ]]; then
  # Unreadable input: fail closed only when Documents is mentioned.
  [[ ${(L)input} == *documents* ]] && deny
  exit 0
fi
cwd=$(field cwd)
[[ -n $cwd ]] || cwd=$PWD

typeset -a candidates
case $tool in
  Read|Edit|MultiEdit|Write)
    candidates=("$(field tool_input.file_path)")
    ;;
  NotebookEdit)
    candidates=("$(field tool_input.notebook_path)")
    ;;
  Grep|Glob)
    root=$(field tool_input.path)
    candidates=("${root:-$cwd}")
    # A pattern can reach outside its root (absolute or ../), so also check
    # the directory its literal prefix points at.
    for key in pattern glob; do
      pat=$(field tool_input.$key)
      [[ -n $pat ]] || continue
      [[ $pat == '~'* ]] && pat=$HOME${pat#\~}
      [[ $pat == /* ]] || pat=${root:-$cwd}/$pat
      lit=${pat%%[*?\[\{]*}x
      candidates+=("${lit:h}")
    done
    ;;
  *)
    exit 0
    ;;
esac

for raw in "${candidates[@]}"; do
  if [[ -z $raw ]]; then
    # Could not read the path: fail closed only when Documents is mentioned.
    [[ ${(L)input} == *documents* ]] && deny
    continue
  fi
  [[ $raw == '~'* ]] && raw=$HOME${raw#\~}
  [[ $raw == /* ]] || raw=$cwd/$raw
  p=${raw:A}
  p=${(L)p}
  [[ $p == $vault || $p == $vault/* ]] && continue
  [[ $p == $docs || $p == $docs/* ]] && deny
  # A search rooted above Documents would sweep through it.
  if [[ $tool == (Grep|Glob) ]] && [[ $p == / || $docs == $p/* ]]; then
    deny
  fi
done
exit 0
