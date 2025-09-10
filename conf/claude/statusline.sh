#!/bin/bash
input=$(cat)

# ANSI Colors
RED_R='\033[0;31m'
GREEN_R='\033[0;32m'
PURPLE_R='\033[0;35m'
BLUE_R='\033[1;94m'
NC='\033[0m'

function model() {
  echo "$input" | jq -r '.model.display_name'
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

function git_branch() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
      echo $BRANCH
    fi
  fi
}

echo -e "$PURPLE_R[$(model)]$NC \
🏗️$BLUE_R$(basename $(project_dir))$NC | \
📂$BLUE_R$(basename $(current_dir))$NC | \
🪵$BLUE_R$(git_branch)$NC | \
$GREEN_R+$(lines_added)$NC/$RED_R-$(lines_removed)$NC | \
💰$BLUE_R\$$(cost)$NC"
