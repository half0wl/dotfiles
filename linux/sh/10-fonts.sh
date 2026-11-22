#!/usr/bin/env bash
# https://github.com/half0wl/dotfiles
#
# 10-fonts.sh
#
# Popular fonts from apt, plus Monaspace (Nerd Font build) from GitHub.
#
# Usage:
#   ./10-fonts.sh [--dry-run] [--yes] [--force]
#
#   --force   re-download Monaspace even if it is installed
#
# Notes:
#   * Monaspace goes to ~/.local/share/fonts/monaspace-<family>/ (user
#     only).
#   * The Nerd Font build's family names end in " NF", e.g.
#     "Monaspace Krypton NF"; use that exact name in configs.
#   * A Monaspace family is only downloaded when fc-list does not know it.

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

APT_FONTS=(
  # UI / sans
  fonts-inter # Inter: the modern UI default
  fonts-roboto # Android / Material
  fonts-open-sans
  fonts-lato
  fonts-adobe-sourcesans3 # Source Sans 3
  fonts-ubuntu

  # Monospace / coding
  fonts-jetbrains-mono
  fonts-firacode
  fonts-cascadia-code
  fonts-hack

  # Coverage: every script + emoji, so nothing renders as tofu boxes
  fonts-noto-core
  fonts-noto-cjk
  fonts-noto-color-emoji

  # Metric-compatible stand-ins for MS fonts (documents and web pages lay
  # out correctly): Liberation = Arial/Times/Courier, Carlito = Calibri,
  # Caladea = Cambria
  fonts-liberation
  fonts-crosextra-carlito
  fonts-crosextra-caladea
  fonts-dejavu
)

# Monaspace families to install: Argon Krypton Neon Radon Xenon
MONASPACE_FAMILIES=(
  Krypton
)
MONASPACE_REPO="githubnext/monaspace"
MONASPACE_ASSET="monaspace-nerdfonts-%s.zip" # %s = release tag

FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

FORCE=0
FONTS_CHANGED=0

parse_args() {
  local a
  for a in "${ARGS[@]}"; do
    case $a in
      -f | --force) FORCE=1 ;;
      *) die "unknown argument: $a (try --help)" ;;
    esac
  done
}

have_family() {
  grep -qxF "$1" <<<"$(fc-list : family | tr ',' '\n')"
}

install_apt_fonts() {
  step "apt fonts"
  local before=$_N_CHANGED
  apt_ensure "${APT_FONTS[@]}"
  ((_N_CHANGED == before)) || FONTS_CHANGED=1
}

# Download the release zip and unpack the requested families.
_install_monaspace() { # tag families...
  local tag=$1 asset tmp fam dest base
  shift
  # shellcheck disable=SC2059  # the asset name pattern is the format
  asset=$(printf "$MONASPACE_ASSET" "$tag")
  base="https://github.com/$MONASPACE_REPO/releases/download"
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' EXIT
  curl -fsSL -o "$tmp/monaspace.zip" "$base/$tag/$asset"
  for fam; do
    dest="$FONT_DIR/monaspace-${fam,,}"
    rm -rf -- "$dest"
    mkdir -p -- "$dest"
    # -j: drop the zip's folders, keep only this family's .otf files
    unzip -qjo "$tmp/monaspace.zip" "*/Monaspace $fam/*.otf" -d "$dest"
  done
}

latest_monaspace_tag() {
  curl -fsSL "https://api.github.com/repos/$MONASPACE_REPO/releases/latest" |
    sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -n1
}

install_monaspace() {
  step "Monaspace"
  local fam
  local -a missing=()
  for fam in "${MONASPACE_FAMILIES[@]}"; do
    if ((FORCE)) || ! have_family "Monaspace $fam NF"; then
      missing+=("$fam")
    else
      skip "Monaspace $fam NF already installed"
    fi
  done
  ((${#missing[@]})) || return 0

  local tag
  tag=$(latest_monaspace_tag)
  [[ -n $tag ]] || die "could not find the latest Monaspace release"
  apply "Monaspace ${missing[*]} NF $tag (~330 MB download)" \
    _install_monaspace "$tag" "${missing[@]}"
  FONTS_CHANGED=1
}

refresh_cache() {
  step "Font cache"
  if ((!FONTS_CHANGED)); then
    skip "no fonts changed; cache is current"
    return 0
  fi
  apply "rebuild font cache" fc-cache -f
  if ((!DRY_RUN)); then
    info "$(fc-list : family | sort -u | wc -l) font families available"
  fi
}

main() {
  lib_init "apt fonts and Monaspace NF" "$@"
  parse_args
  require_user
  need_sudo
  require_cmd curl unzip fc-list fc-cache

  install_apt_fonts
  install_monaspace
  refresh_cache
}

main "$@"
