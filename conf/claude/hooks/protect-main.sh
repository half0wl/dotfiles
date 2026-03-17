#!/usr/bin/env bash
# Hook: block commits and pushes to main/master branches

cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

# Block git commit on main/master
if [[ "$cmd" =~ git[[:space:]]+commit ]]; then
  branch=$(git branch --show-current 2>/dev/null)
  if [[ "$branch" =~ ^(main|master)$ ]]; then
    printf '{"decision":"block","reason":"Committing directly to %s is not allowed. Create a feature branch first."}' "$branch"
    exit 0
  fi
fi

# Block git push to main/master
if [[ "$cmd" =~ git[[:space:]]+push ]]; then
  # Block if main/master appears as a target in the command
  if [[ "$cmd" =~ [[:space:]](main|master)(:|[[:space:]]|$) ]]; then
    printf '{"decision":"block","reason":"Pushing to main/master is not allowed. Use a feature branch and PR."}'
    exit 0
  fi
  # Block if on main/master with no explicit branch (implicit push of current branch)
  branch=$(git branch --show-current 2>/dev/null)
  if [[ "$branch" =~ ^(main|master)$ ]]; then
    printf '{"decision":"block","reason":"Pushing to %s is not allowed. Use a feature branch and PR."}' "$branch"
    exit 0
  fi
fi
