#!/usr/bin/env bash
#
# format-markdown.sh
# https://github.com/half0wl/dotfiles
#
# Formats all Markdown (`*.md`) files in a Git repository using Prettier.
#
# This script rewraps prose at 79 characters, and normalizes the rest of the
# content (e.g. lists, tables, emphasis, spacing, etc.) to Prettier's
# standard style. Headings, long URLs, tables and code blocks can't be
# wrapped, so their lines stay as long as they are.
#
# ONLY works on Git repositories. Requires mise (https://mise.jdx.dev) and a
# `format-markdown.mise.toml` next to this script that pins Bun and Prettier;
# mise installs them on first run and reuses them after that. Other installs
# of either are never used.
#
# This script always runs from the root of the Git repository it lives in
# regardless of where it's invoked in the repo's directory tree, and
# recursively formats every `*.md` file under it.
#
# It honors `.gitignore` (including nested ones), `.git/info/exclude`, &
# global excludes.
#
# Any existing `.prettierrc` or `.editorconfig`, including ones in parent
# dirs, are ignored. A `.prettierignore` at the repository root is still
# honored, though: files listed in it are skipped. If the repository has its
# own Prettier setup (a `.prettierrc*`, `prettier.config.*`, or a
# `package.json` that mentions Prettier), the script warns but carries on,
# since editors that format on save use that setup instead and the two may
# keep undoing each other's changes.
#
# Usage:
#
#   ./format-markdown.sh           Format every `*.md` file in place. If >10
#                                  files need formatting, it lists them and
#                                  asks to proceed first, or stops if there
#                                  is no terminal to ask on (use `--yes` to
#                                  bypass this behaviour).
#
#   ./format-markdown.sh --check   List files that need formatting. Exits
#                                  non-zero if any do, so it can function
#                                  as a CI gate or pre-commit hook.
#
#   ./format-markdown.sh --count   Print a count of files that need
#                                  formatting.
#
#   ./format-markdown.sh --yes     Same as the default, but never asks to
#                                  proceed regardless of however many files
#                                  will be formatted.
#
#   ./format-markdown.sh --help    Show a summary of the above.
#
# To use this script in other repositories:
#
#   1. Place `format-markdown.sh` & `format-markdown.mise.toml` in the same
#      directory anywhere in the repository. Nothing in either needs editing.
#
#   2. You may need to `mise trust` it once per clone:
#
#      ```sh
#      mise trust path/to/format-markdown.mise.toml
#      ```
#
#      In CI, where every run starts fresh, set `MISE_TRUSTED_CONFIG_PATHS`
#      to the script's directory instead.
#
set -euo pipefail

# Rewriting more files than this asks for confirmation first, and the prompt
# lists at most MAX_LISTED of them.
CONFIRM_ABOVE=10
MAX_LISTED=25

# Errors follow the usual Unix shape: "name: message" on stderr. Exit codes
# follow grep, diff and Prettier: 1 means "found something" (files that need
# formatting) and 2 means trouble, so CI can tell the two apart.
prog="./$(basename -- "$0")"

# Messages all go to stderr, so color them only when stderr is a terminal
# and NO_COLOR isn't set.
yellow=""
reset=""
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  yellow=$'\e[0;33m'
  reset=$'\e[0m'
fi

die() {
  echo "$prog: $*" >&2
  exit 2
}

usage_error() {
  echo "$prog: $*" >&2
  echo "Try '$prog --help' for more information." >&2
  exit 2
}

show_help() {
  local limit="$CONFIRM_ABOVE"
  cat <<EOF
Usage: $prog [OPTION]...

Formats all Markdown (\`*.md\`) files in a Git repository using Prettier.

This script rewraps prose at 79 characters, and normalizes the rest of the
content (e.g. lists, tables, emphasis, spacing, etc.) to Prettier's
standard style. Headings, long URLs, tables and code blocks can't be
wrapped, so their lines stay as long as they are.

ONLY works on Git repositories. Requires mise (https://mise.jdx.dev) and a
\`format-markdown.mise.toml\` next to this script that pins Bun and Prettier;
mise installs them on first run and reuses them after that. Other installs
of either are never used.

mise must trust the config once per clone:

  mise trust path/to/format-markdown.mise.toml

In CI, where every run starts fresh, set \`MISE_TRUSTED_CONFIG_PATHS\` to the
script's directory instead.

This script always runs from the root of the Git repository it lives in
regardless of where it's invoked in the repo's directory tree, and
recursively formats every \`*.md\` file under it.

It honors \`.gitignore\` (including nested ones), \`.git/info/exclude\`, &
global excludes.

Any existing \`.prettierrc\` or \`.editorconfig\`, including ones in parent
dirs, are ignored. A \`.prettierignore\` at the repository root is still
honored, though: files listed in it are skipped. If the repository has its
own Prettier setup (a \`.prettierrc*\`, \`prettier.config.*\`, or a
\`package.json\` that mentions Prettier), the script warns but carries on,
since editors that format on save use that setup instead and the two may
keep undoing each other's changes.

Options:
      --check   List files that need formatting, and write nothing. Exits 1
                if any do, so it can work as a CI gate or pre-commit hook.
      --count   Print how many files need formatting, and write nothing.
  -y, --yes     Never ask to proceed, regardless of how many files need
                formatting. Without it, if more than $limit do, the script
                lists them and asks first, or stops if there's no terminal.
  -h, --help    Show this help.

<https://github.com/half0wl/dotfiles>
EOF
  exit 0
}

mode="write"
assume_yes=false
for arg in "$@"; do
  case "$arg" in
  --check | --count)
    if [ "$mode" != write ]; then
      usage_error "--check and --count can't be used together"
    fi
    mode="${arg#--}"
    ;;
  -y | --yes) assume_yes=true ;;
  -h | --help) show_help ;;
  *) usage_error "unrecognized option '$arg'" ;;
  esac
done

# Find this file's real location. readlink -f follows symlinks (e.g. a copy
# linked onto PATH), and BASH_SOURCE names this file rather than whatever
# command started it.
script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
script_dir="$(dirname -- "$script_path")"

# The repository root is the top of the git repository this file is in, not
# the one you happen to run it from.
if ! repo_root="$(git -C "$script_dir" rev-parse --show-toplevel \
  2>/dev/null)"; then
  die "$script_dir isn't in a git repository; run git init"
fi

# This script's own mise config lives next to it. The errors below print
# what it should contain, so a copied script can always be set up again.
config_name="format-markdown.mise.toml"
config_file="$script_dir/$config_name"
config_example='[settings]
npm.package_manager = "bun"

[tools]
bun = "1.4.4"
"npm:prettier" = "3.10.1"'

die_with_config_example() {
  {
    echo "$prog: $*"
    echo
    while IFS= read -r line; do
      if [ -n "$line" ]; then
        echo "  $line"
      else
        echo
      fi
    done <<<"$config_example"
  } >&2
  exit 2
}

if [ ! -f "$config_file" ]; then
  die_with_config_example "no $config_file; create it with:"
fi

# Run mise from this file's directory, and tell it to look only for this
# script's config name. That keeps the repository's own mise.toml (its pins,
# [env], hooks and trust state) out of it entirely.
run_mise() {
  (cd "$script_dir" &&
    MISE_OVERRIDE_CONFIG_FILENAMES="$config_name" mise "$@")
}

# mise refuses configs it hasn't been told to trust. Check first, so the
# error says exactly what to run rather than surfacing mise's own.
trust_status="$(run_mise trust --show)" ||
  die "mise couldn't check whether $config_file is trusted"
if grep -q ': untrusted$' <<<"$trust_status"; then
  {
    echo "$prog: mise doesn't trust $config_file yet. Run:"
    echo
    echo "  mise trust $config_file"
    echo
    echo "In CI, set MISE_TRUSTED_CONFIG_PATHS=$script_dir instead."
  } >&2
  exit 2
fi

# Bun and Prettier must be pinned in that exact file. Otherwise mise would
# quietly fall back to whatever your global config, or another
# $config_name further up, has. mise ls reports where each pin came from.
for tool in bun npm:prettier; do
  source_path="$(run_mise ls --local --json "$tool" |
    sed -n 's/^ *"path": *"\(.*\)",\{0,1\}$/\1/p' | head -n 1)" ||
    die "mise couldn't read $config_file (see its error above)"
  if [ "$source_path" != "$config_file" ]; then
    die_with_config_example "$tool isn't pinned in $config_file;" \
      "it should contain:"
  fi
done

# Install the pinned Bun and Prettier if needed. Naming the tools stops mise
# installing everything in your global config too.
run_mise install --quiet bun npm:prettier ||
  die "mise couldn't install Bun and Prettier (see its error above)"

# Use the exact pinned binaries, never a lookup on PATH. Otherwise any other
# prettier or bun earlier on PATH would win: a global npm, pnpm or Homebrew
# install, or a node_modules/.bin added by direnv or a mise [env] setting.
bun_bin="$(run_mise which bun)" ||
  die "mise couldn't find the pinned Bun (see its error above)"
prettier_bin="$(run_mise which prettier)" ||
  die "mise couldn't find the pinned Prettier (see its error above)"

cd "$repo_root"

# Warn when the repository has its own Prettier setup: a config file, or a
# package.json with Prettier as a dependency or config key. Editors format on
# save with that setup, while this script ignores it, so the two could keep
# undoing each other's changes to the same files.
own_prettier=()
while IFS= read -r -d '' file; do
  if [ ! -f "$file" ]; then
    continue
  fi
  case "$(basename -- "$file")" in
  .prettierrc | .prettierrc.* | prettier.config.*) own_prettier+=("$file") ;;
  package.json)
    if grep -q '"prettier"[[:space:]]*:' -- "$file"; then
      own_prettier+=("$file")
    fi
    ;;
  esac
done < <(git ls-files -z --cached --others --exclude-standard)

if [ "${#own_prettier[@]}" -gt 0 ]; then
  {
    echo "$prog: ${yellow}warning:${reset} this repository has its own" \
      "Prettier setup,"
    echo "which this script ignores:"
    for file in "${own_prettier[@]:0:5}"; do
      echo "  - $file"
    done
    if [ "${#own_prettier[@]}" -gt 5 ]; then
      echo "  - ... and $((${#own_prettier[@]} - 5)) more"
    fi
    echo "Editors that format on save use that setup instead, so the two may"
    echo "keep undoing each other's changes."
    echo
  } >&2
fi

# Ask git which files count: tracked ones, plus untracked ones it doesn't
# ignore. Files deleted from disk but still tracked are skipped.
targets=()
while IFS= read -r -d '' file; do
  if [ -f "$file" ]; then
    targets+=("$file")
  fi
done < <(git ls-files -z --cached --others --exclude-standard -- '*.md')

if [ "${#targets[@]}" -eq 0 ]; then
  if [ "$mode" = count ]; then
    echo 0
  fi
  exit 0
fi

# Prettier's launcher calls `node`, and depending on how mise installed it,
# it may be a shell shim rather than the JS file itself. So put a `node` that
# is really Bun first on PATH: Bun acts as Node when it's run by that name.
# This also stops any other Node on PATH being picked up.
node_shim_dir="$(mktemp -d)"
trap 'rm -rf -- "$node_shim_dir"' EXIT
ln -s -- "$bun_bin" "$node_shim_dir/node"

run_prettier() {
  PATH="$node_shim_dir:$PATH" "$prettier_bin" \
    --no-config --no-editorconfig \
    --prose-wrap always --print-width 79 \
    "$@"
}

# Find the files Prettier would change. --list-different exits 1 when it
# finds any, which is expected; 2 means Prettier itself failed, and it has
# already printed why. It needs the default log level, or it prints nothing.
list_status=0
list_output="$(run_prettier --list-different -- "${targets[@]}")" ||
  list_status=$?
if [ "$list_status" -gt 1 ]; then
  exit "$list_status"
fi
needs_formatting=()
if [ -n "$list_output" ]; then
  mapfile -t needs_formatting <<<"$list_output"
fi

if [ "$mode" = count ]; then
  echo "${#needs_formatting[@]}"
  exit 0
fi

# Print bare paths, one per line, rather than Prettier's --check output with
# its "[warn]" prefixes and summary line. Exit 1 if any need formatting.
if [ "$mode" = check ]; then
  if [ "${#needs_formatting[@]}" -eq 0 ]; then
    exit 0
  fi
  printf '%s\n' "${needs_formatting[@]}"
  exit 1
fi

if [ "${#needs_formatting[@]}" -eq 0 ]; then
  exit 0
fi

# List the files and ask before going ahead.
confirm() {
  local count="${#needs_formatting[@]}"
  local path answer

  {
    # The Prettier-setup warning already ends with a blank line.
    if [ "${#own_prettier[@]}" -eq 0 ]; then
      printf '\n'
    fi
    printf '⚠️ There are %d Markdown files that will be formatted' "$count"
    printf ' by this script:\n\n'
    for path in "${needs_formatting[@]:0:MAX_LISTED}"; do
      printf '  - %s%s%s\n' "$yellow" "$path" "$reset"
    done
    if [ "$count" -gt "$MAX_LISTED" ]; then
      printf '  - ...\n\n'
      printf "For the full list, run \`%s --check\`.\n" "$prog"
    fi
    printf '\n'
  } >&2

  if [ ! -t 0 ]; then
    die "can't ask to proceed without a terminal; pass --yes to skip it"
  fi
  read -r -p "Proceed? [y/n] " answer
  case "$answer" in
  y | Y | yes | Yes | YES) return 0 ;;
  esac
  echo "$prog: aborted" >&2
  return 1
}

if [ "$assume_yes" = false ] &&
  [ "${#needs_formatting[@]}" -gt "$CONFIRM_ABOVE" ]; then
  confirm || exit 1
fi

run_prettier --write --log-level warn -- "${needs_formatting[@]}"
