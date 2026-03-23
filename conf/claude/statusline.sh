#!/bin/bash
input=$(cat)

# ANSI Colors
RED_R='\033[0;31m'
GREEN_R='\033[0;32m'
PURPLE_R='\033[0;35m'
BLUE_R='\033[1;94m'
NC='\033[0m'

function model() {
  echo "$input" | jq -r '.model.id | sub("^claude-"; "")'
}

function current_dir() {
  echo "$input" | jq -r '.workspace.current_dir'
}

function project_dir() {
  echo "$input" | jq -r '.workspace.project_dir'
}

function cost() {
  echo "$input" | jq -r '.cost.total_cost_usd' | xargs printf "%.2f"
}

function lines_added() {
  echo "$input" | jq -r '.cost.total_lines_added'
}

function lines_removed() {
  echo "$input" | jq -r '.cost.total_lines_removed'
}

function session_time() {
  local ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
  local total_secs=$((ms / 1000))
  local mins=$((total_secs / 60))
  local secs=$((total_secs % 60))
  printf "%dm%02ds" "$mins" "$secs"
}

function context_usage() {
  local pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
  local color="$GREEN_R"
  if [ "$pct" -ge 75 ]; then
    color="$RED_R"
  fi
  printf "${color}%d%%${NC}" "$pct"
}

function git_branch() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
      echo $BRANCH
    fi
  fi
}

PROJECT=$(basename $(project_dir))
CURRENT=$(basename $(current_dir))

if [ "$PROJECT" = "$CURRENT" ]; then
  DIR_SEGMENT="📁$BLUE_R$PROJECT$NC"
else
  DIR_SEGMENT="📁$BLUE_R$PROJECT$NC/$BLUE_R$CURRENT$NC"
fi

echo -e "🤖$PURPLE_R$(model)$NC $DIR_SEGMENT ⚡️$(context_usage)@$GREEN_R$(session_time)$NC@$GREEN_R+$(lines_added)$NC$RED_R-$(lines_removed)$NC=$BLUE_R\$$(cost)$NC"
