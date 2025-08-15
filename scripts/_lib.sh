# ========================================================================== #
# https://github.com/half0wl/toolkit                                         #
# MIT License - (c) 2025 Ray Chen <meow@ray.cat>                             #
#                                                                            #
# _lib.sh - A set of utility functions for shell scripts.                    #
# To use this, run `source _lib.sh` in a shell script.                       #
#                                                                            #
# Available Functions:                                                       #
#                                                                            #
#   write_info(message)      - Print informational message                   #
#   write_ok(message)        - Print successful message                      #
#   write_warning(message)   - Print warning message                         #
#   write_error(message)     - Print error message                           #
#   write_busy(message)      - Start progress spinner with message           #
#   write_done([message?])   - Stop spinner, optionally show completion msg  #
#   confirm(prompt, default) - Show confirmation prompt, return true/false   #
#   is_dry_run($@)           - Check if --dry-run flag is present            #
#                                                                            #
# ========================================================================== #

# ANSI Colors - Regular
BLACK_R='\e[0;30m'
RED_R='\e[0;31m'
GREEN_R='\e[0;32m'
YELLOW_R='\e[0;33m'
BLUE_R='\e[0;34m'
PURPLE_R='\e[0;35m'
CYAN_R='\e[0;36m'
WHITE_R='\e[0;37m'

# ANSI Colors - Bold
BLACK_B='\e[1;30m'
RED_B='\e[1;31m'
GREEN_B='\e[1;32m'
YELLOW_B='\e[1;33m'
BLUE_B='\e[1;34m'
PURPLE_B='\e[1;35m'
CYAN_B='\e[1;36m'
WHITE_B='\e[1;37m'

# ANSI Colors - Underline
BLACK_U='\e[4;30m'
RED_U='\e[4;31m'
GREEN_U='\e[4;32m'
YELLOW_U='\e[4;33m'
BLUE_U='\e[4;34m'
PURPLE_U='\e[4;35m'
CYAN_U='\e[4;36m'
WHITE_U='\e[4;37m'

# ANSI Colors - Background
BLACK_BG='\e[40m'
RED_BG='\e[41m'
GREEN_BG='\e[42m'
YELLOW_BG='\e[43m'
BLUE_BG='\e[44m'
PURPLE_BG='\e[45m'
CYAN_BG='\e[46m'
WHITE_BG='\e[47m'

# ANSI Colors - High Intensity
BLACK_HI='\e[0;90m'
RED_HI='\e[0;91m'
GREEN_HI='\e[0;92m'
YELLOW_HI='\e[0;93m'
BLUE_HI='\e[0;94m'
PURPLE_HI='\e[0;95m'
CYAN_HI='\e[0;96m'
WHITE_HI='\e[0;97m'

# ANSI Colors - Bold High Intensity
BLACK_BHI='\e[1;90m'
RED_BHI='\e[1;91m'
GREEN_BHI='\e[1;92m'
YELLOW_BHI='\e[1;93m'
BLUE_BHI='\e[1;94m'
PURPLE_BHI='\e[1;95m'
CYAN_BHI='\e[1;96m'
WHITE_BHI='\e[1;97m'

# ANSI Colors - High Intensity Background
BLACK_HIBG='\e[0;100m'
RED_HIBG='\e[0;101m'
GREEN_HIBG='\e[0;102m'
YELLOW_HIBG='\e[0;103m'
BLUE_HIBG='\e[0;104m'
PURPLE_HIBG='\e[0;105m'
CYAN_HIBG='\e[0;106m'
WHITE_HIBG='\e[0;107m'

# ANSI - Text Styles
BOLD='\e[1m'
ITALIC='\e[3m'
UNDERLINE='\e[4m'
STRIKETHROUGH='\e[9m'

# ANSI - Reset
NC='\e[0m'

# Globals
PROGRESS_SPINNER_PID=""

# write_info() prints an informational message in cyan.
#
# Arguments:
#
#   $1 - Message to print
#
# Usage:
#
#   write_info "This is an informational message"
function write_info() {
  printf '%b%s%b\n' "${CYAN_R}[ I ] " "${1}" "${NC}"
}

# write_ok() prints a successful message in green.
#
# Arguments:
#
#   $1 - Message to print
#
# Usage:
#
#   write_ok "This is an ok message"
function write_ok() {
  printf '%b%s%b\n' "${GREEN_R}[ ✔ ] " "${1}" "${NC}"
}

# write_warning() prints a warning message in yellow.
#
# Arguments:
#
#   $1 - Message to print
#
# Usage:
#
#   write_warning "This is a warning message"
function write_warning() {
  printf '%b%s%b\n' "${YELLOW_R}[ ⚠ ] " "${1}" "${NC}"
}

# write_error() prints an error message in red.
#
# Arguments:
#
#   $1 - Error message to print
#
# Usage:
#
#   write_error "An error occurred while processing the request"
function write_error() {
  printf '%b%s%b\n' "${RED_B}[ X ] " "${1}" "${NC}"
}

# write_busy() shows a progress spinner indicating that a task is in progress.
#
# Arguments:
#
#   $1 - Message to display (will have "..." appended)
#
# Usage:
#
#   write_busy "Compiling source code"
#   make all
#
#   write_busy "Running tests"
#   make test
#
#   stop_spinner
#   echo "Build complete!"
function write_busy() {
  _progress_spinner_stop
  _progress_spinner_start "$1..."
}

# write_done() stops the active progress spinner indicating that a task has
# finished.
#
# Arguments:
#
#   $1 - Optional completion message to display
#
# Usage:
#
#   write_busy "Processing"
#   sleep 2
#   write_done "Complete"
#
#   # Or just stop and move to next line
#   write_busy "Loading"
#   sleep 1
#   write_done
function write_done() {
  if [[ -n "${PROGRESS_SPINNER_PID}" ]] &&
    kill -0 "${PROGRESS_SPINNER_PID}" 2>/dev/null; then
    kill "${PROGRESS_SPINNER_PID}" >/dev/null 2>&1
    wait "${PROGRESS_SPINNER_PID}" 2>/dev/null || true
    PROGRESS_SPINNER_PID=""
  fi
  trap - $(seq 0 15)
  printf '\r\033[2K\e[?25h'
  if [[ -n "${1:-}" ]]; then
    printf '%b%s%b\n' "${GREEN_B}[ ✔ ] " "${1}" "${NC}"
  fi
}

# confirm() shows a confirmation prompt to the user and returns true if the
# user inputs 'y' / 'Y', false otherwise.
#
# Arguments:
#
#   $1 - Confirmation prompt message to display
#   $2 - Default value ("Y" or "N", defaults to "N" if not specified)
#
# Usage:
#
#   if confirm "Continue?"; then
#     # yes
#   else
#     # no
#     exit 1
#   fi
#
# Examples:
#
#   confirm "Delete all files?"               # Defaults to No [y/N]
#   confirm "Proceed with installation?" "Y"  # Defaults to Yes [Y/n]
confirm() {
  local prompt="$1"
  local default="$2"
  default=${default:-"N"}
  if [ "$default" = "Y" ]; then
    echo ""
    prompt="$prompt [Y/n]: "
  else
    echo ""
    prompt="$prompt [y/N]: "
  fi
  read -r -p "$prompt" response
  if [ -z "$response" ]; then
    response=$default
  fi
  if [[ "$response" =~ ^[Yy]$ ]]; then
    return 0
  else
    write_error "Operation cancelled."
    return 1
  fi
}

# is_dry_run() returns true if --dry-run flag is provided, false otherwise.
#
# Arguments:
#
#   $@ - All command line arguments to check
#
# Usage:
#
#   DRY_RUN=$(is_dry_run "$@")
#   if [ "$DRY_RUN" = "true" ]; then
#       echo "dryrun"
#   else
#       echo "normal"
#   fi
#
# Example in a script:
#
#   #!/bin/bash
#   DRY_RUN=$(is_dry_run "$@")
#   if [ "$DRY_RUN" = "true" ]; then
#     echo "DRY RUN: Would delete file.txt"
#   else
#     rm file.txt
#     echo "Deleted file.txt"
#   fi
is_dry_run() {
  local dry_run=false
  for arg in "$@"; do
    case $arg in
    --dry-run)
      dry_run=true
      break
      ;;
    esac
  done
  echo "$dry_run"
}

# _progress_spinner_draw() draws a progress spinner.
function _progress_spinner_draw() {
  local -a marks=('⠋ ○' '⠙○ ' ' ⠹ ' '○⠸ ' ' ⠼○' ' ⠴ ' ' ⠦ ' '○⠧ ' ' ⠇○' ' ⠏ ')
  local i=0
  while :; do
    printf "\r%b%s [RUNNING]%b %s" \
      " ${PURPLE_BHI}" "${marks[i++ % ${#marks[@]}]}" "${NC}" \
      "${1:-}"
    printf '\e[?25l'
    sleep 0.1
  done
}

# _progress_spinner_stop() stops the active progress spinner.
function _progress_spinner_stop() {
  if [[ -n "${PROGRESS_SPINNER_PID}" ]] && kill -0 "${PROGRESS_SPINNER_PID}" 2>/dev/null; then
    kill "${PROGRESS_SPINNER_PID}" >/dev/null 2>&1
    wait "${PROGRESS_SPINNER_PID}" 2>/dev/null || true
    PROGRESS_SPINNER_PID=""
  fi
  trap - $(seq 0 15)
  printf '\e[?25h'
}

# _progress_spinner_start() starts a progress spinner.
#
# Arguments:
#
#   $1 - Optional message to display next to the spinner
function _progress_spinner_start() {
  _progress_spinner_stop
  message=${1:-}
  _progress_spinner_draw "${message}" &
  PROGRESS_SPINNER_PID=$!
  trap _progress_spinner_stop $(seq 0 15)
}
