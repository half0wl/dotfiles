#!/bin/bash
# ========================================================================== #
# https://github.com/half0wl/toolkit                                         #
# MIT License (c) 2025 Ray Chen <meow@ray.cat>                               #
#                                                                            #
# setup.sh - Set up a macOS system for development.                          #
#                                                                            #
# Usage:                                                                     #
#                                                                            #
#   ./setup.sh <hostname> # Where <hostname> is your desired hostname for    #
#                          # your system, e.g. "rays-macbook-pro"            #
#                                                                            #
# ========================================================================== #

set -eou pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

BREW_DEPS=(
  # Common
  "tmux"
  "neovim"
  "coreutils"
  "direnv"
  "wget"
  "fd"

  # Tools
  "rg"
  "yq"
  "gh"
  "dive"
  "lima"
  "k9s"
  "gcloud-cli"
  "grpcurl"
  "grip"
  "gitui"
  "mtr"
  "tree"

  # Databases
  "postgresql@17"
  "redis"

  # Languages
  "go"
  "rust"
  "pyenv"
  "nvm"
  "npm"
  "pnpm"
  "poetry"
  "protobuf"

  # Misc.
  "exiftool"
)

BREW_CASK_DEPS=(
  # Tools
  "orbstack"
  "tableplus"

  # Fonts
  "font-inter"
  "font-monaspace"
  "font-mona-sans"
  "font-inter-tight"
  "font-noto-sans"
  "font-open-sans"
  "font-pt-serif"
  "font-cormorant"
  "font-cormorant-garamond"
)

# ========================================================================== #

setup_pi() {
  write_info "setting up pi config..."
  mkdir -p ~/.pi/agent
  if [[ -e ~/.pi/agent/settings.json || -L ~/.pi/agent/settings.json ]]; then
    write_warn "removing existing ~/.pi/agent/settings.json"
    rm -f ~/.pi/agent/settings.json
  fi
  ln -s ~/dotfiles/conf/pi/agent/settings.json ~/.pi/agent/settings.json
  write_ok "--> ~/.pi/agent/settings.json"

  if [[ -e ~/.pi/agent/SYSTEM.md || -L ~/.pi/agent/SYSTEM.md ]]; then
    write_warn "removing existing ~/.pi/agent/SYSTEM.md"
    rm -f ~/.pi/agent/SYSTEM.md
  fi
  ln -s ~/dotfiles/conf/pi/agent/SYSTEM.md ~/.pi/agent/SYSTEM.md
  write_ok "--> ~/.pi/agent/SYSTEM.md"

  if [[ -e ~/.pi/agent/themes || -L ~/.pi/agent/themes ]]; then
    write_warn "removing existing ~/.pi/agent/themes"
    rm -rf ~/.pi/agent/themes
  fi
  ln -s ~/dotfiles/conf/pi/themes ~/.pi/agent/themes
  write_ok "--> ~/.pi/agent/themes"

  if [[ -e ~/.pi/agent/extensions || -L ~/.pi/agent/extensions ]]; then
    write_warn "removing existing ~/.pi/agent/extensions"
    rm -rf ~/.pi/agent/extensions
  fi
  ln -s ~/dotfiles/conf/pi/extensions ~/.pi/agent/extensions
  write_ok "--> ~/.pi/agent/extensions"
}

if [[ $# -eq 0 ]]; then
  echo "Usage   : $0 <hostname>"
  echo "Example : $0 rays-macbook-pro"
  echo
  echo "Subcommands:"
  echo "  $0 pi    # set up pi config + symlinks only (no install)"
  exit 1
fi

if [[ "$1" == "pi" ]]; then
  setup_pi
  write_ok "pi setup complete"
  exit 0
fi

hostname="$1"

write_info "configurationg macOS system..."
write_info "setting system hostname to $hostname"
sudo scutil --set HostName $hostname
sudo scutil --set ComputerName $hostname
sudo scutil --set LocalHostName $hostname
write_ok "hostname -> $hostname"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
write_ok "firewall -> on"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
write_ok "firewall stealth mode -> on"
defaults write -g AppleShowAllFiles -bool true
killall Finder
write_ok "finder hidden files -> on"
write_ok "macOS system config completed"

# ========================================================================== #

write_info "installing Xcode dev tools..."
if xcode-select -p &>/dev/null; then
  write_ok "Xcode dev tools already installed, skipping"
else
  xcode-select --install
  sleep 1.5
  osascript <<EOD
      tell application "System Events"
        tell process "Install Command Line Developer Tools"
          keystroke return
          click button "Agree" of window "License Agreement"
        end tell
      end tell
EOD
  write_ok "Xcode dev tools installed"
fi

# ========================================================================== #

write_info "installng Rosetta..."
/usr/sbin/softwareupdate --install-rosetta --agree
write_ok "rosetta installed"

# ========================================================================== #

if [[ -e "${ZDOTDIR:-$HOME}/.zprezto" || -L "${ZDOTDIR:-$HOME}/.zprezto" ]]; then
  write_ok "zprezto already installed, skipping"
else
  write_info "installing zprezto..."
  git clone \
    --recursive \
    https://github.com/sorin-ionescu/prezto.git \
    "${ZDOTDIR:-$HOME}/.zprezto"
  write_ok "zprezto installed"
fi
write_info "changing shell to zsh..."
chsh -s /bin/zsh
write_ok "shell changed to zsh"

# ========================================================================== #

write_info "installing brew..."
if command -v brew >/dev/null 2>&1; then
  write_ok "brew already installed, skipping"
else
  /bin/bash \
    -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  write_ok "brew installed"
fi

write_info "turning off brew analytics"
brew analytics off
write_ok "brew analytics -> off"

# ========================================================================== #

write_info "installing brew dependencies..."
printf ' - %s\n' "${BREW_DEPS[@]}"
brew install "${BREW_DEPS[@]}"
write_ok "brew dependencies installed"

# ========================================================================== #

write_info "installing brew-cask dependencies..."
printf ' - %s\n' "${BREW_CASK_DEPS[@]}"
brew install "${BREW_CASK_DEPS[@]}"
write_ok "brew cask dependencies installed"

# ========================================================================== #

write_info "setting up directories..."
mkdir -p ~/.cache
mkdir -p ~/.claude
mkdir -p ~/.config
mkdir -p ~/.config/nvim
mkdir -p ~/.config/gitui
mkdir -p ~/.config/tmux/plugins
mkdir -p ~/.agents
mkdir -p ~/.pi/agent
sudo chown -R $(whoami) ~/.cache
sudo chown -R $(whoami) ~/.claude
sudo chown -R $(whoami) ~/.config
sudo chown -R $(whoami) ~/.config/nvim
sudo chown -R $(whoami) ~/.config/gitui
sudo chown -R $(whoami) ~/.pi
write_ok "directories set up complete"

# ========================================================================== #

write_info "creating configuration symlinks..."

if [[ -e ~/.zshrc || -L ~/.zshrc ]]; then
  write_warn "removing existing ~/.zshrc"
  rm -f ~/.zshrc
fi
ln -s ~/dotfiles/conf/.zshrc ~/.zshrc
write_ok "--> ~/.zshrc"

if [[ -e ~/.zpreztorc || -L ~/.zpreztorc ]]; then
  write_warn "removing existing ~/.zpreztorc"
  rm -f ~/.zpreztorc
fi
ln -s ~/dotfiles/conf/.zpreztorc ~/.zpreztorc
write_ok "--> ~/.zpreztorc"

if [[ -e ~/.tmux.conf || -L ~/.tmux.conf ]]; then
  write_warn "removing existing ~/.tmux.conf"
  rm -f ~/.tmux.conf
fi
ln -s ~/dotfiles/conf/.tmux.conf ~/.tmux.conf
write_ok "--> ~/.tmux.conf"

if [[ -e ~/.config/nvim || -L ~/.config/nvim ]]; then
  write_warn "removing existing ~/.config/nvim"
  rm -rf ~/.config/nvim
fi
ln -s ~/dotfiles/nvim ~/.config/nvim
write_ok "--> ~/.config/nvim"

if [[ -e ~/.gitconfig || -L ~/.gitconfig ]]; then
  write_warn "removing existing ~/.gitconfig"
  rm -f ~/.gitconfig
fi
ln -s ~/dotfiles/conf/.gitconfig ~/.gitconfig
write_ok "--> ~/.gitconfig"

if [[ -e ~/.gitignore_global || -L ~/.gitignore_global ]]; then
  write_warn "removing existing ~/.gitignore_global"
  rm -f ~/.gitignore_global
fi
ln -s ~/dotfiles/conf/.gitignore_global ~/.gitignore_global
write_ok "--> ~/.gitignore_global"

if [[ -e ~/.claude/settings.json || -L ~/.claude/settings.json ]]; then
  write_warn "removing existing ~/.claude/settings.json"
  rm -f ~/.claude/settings.json
fi
ln -s ~/dotfiles/conf/claude/settings.json ~/.claude/settings.json
write_ok "--> ~/.claude/settings.json"

if [[ -e ~/.claude/statusline.sh || -L ~/.claude/statusline.sh ]]; then
  write_warn "removing existing ~/.claude/statusline.sh"
  rm -f ~/.claude/statusline.sh
fi
ln -s ~/dotfiles/conf/claude/statusline.sh ~/.claude/statusline.sh
write_ok "--> ~/.claude/statusline.sh"

if [[ -e ~/.claude/CLAUDE.md || -L ~/.claude/CLAUDE.md ]]; then
  write_warn "removing existing ~/.claude/CLAUDE.md"
  rm -f ~/.claude/CLAUDE.md
fi
ln -s ~/dotfiles/conf/claude/CLAUDE.md ~/.claude/CLAUDE.md
write_ok "--> ~/.claude/CLAUDE.md"

if [[ -e ~/.claude/hooks || -L ~/.claude/hooks ]]; then
  write_warn "removing existing ~/.claude/hooks"
  rm -rf ~/.claude/hooks
fi
ln -s ~/dotfiles/conf/claude/hooks ~/.claude/hooks
write_ok "--> ~/.claude/hooks"

if [[ -e ~/.claude/skills || -L ~/.claude/skills ]]; then
  write_warn "removing existing ~/.claude/skills"
  rm -rf ~/.claude/skills
fi
ln -s ~/dotfiles/conf/claude/skills ~/.claude/skills
write_ok "--> ~/.claude/skills"

if [[ -e ~/.agents/skills || -L ~/.agents/skills ]]; then
  write_warn "removing existing ~/.agents/skills"
  rm -rf ~/.agents/skills
fi
ln -s ~/dotfiles/conf/claude/skills ~/.agents/skills
write_ok "--> ~/.agents/skills"

setup_pi

GHOSTTY_CONF_PATH="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
if [[ -e "$GHOSTTY_CONF_PATH" || -L "$GHOSTTY_CONF_PATH" ]]; then
  write_warn "removing existing $GHOSTTY_CONF_PATH"
  rm -f "$GHOSTTY_CONF_PATH"
fi
ln -s ~/dotfiles/conf/ghostty/config "$GHOSTTY_CONF_PATH"
write_ok "--> $GHOSTTY_CONF_PATH"

if [[ -e ~/.config/gitui/theme.ron || -L ~/.config/gitui/theme.ron ]]; then
  write_warn "removing existing ~/.config/gitui/theme.ron"
  rm -f ~/.config/gitui/theme.ron
fi
ln -s ~/dotfiles/conf/gitui/theme.ron ~/.config/gitui/theme.ron
write_ok "--> ~/.config/gitui/theme.ron"

for plugin in ~/dotfiles/conf/tmux-plugins/*; do
  plugin_name=$(basename "$plugin")
  chmod +x "$plugin"
  if [[ -e ~/.config/tmux/plugins/"$plugin_name" || -L ~/.config/tmux/plugins/"$plugin_name" ]]; then
    write_warn "removing existing ~/.config/tmux/plugins/$plugin_name"
    rm -f ~/.config/tmux/plugins/"$plugin_name"
  fi
  ln -s "$plugin" ~/.config/tmux/plugins/"$plugin_name"
  write_ok "--> ~/.config/tmux/plugins/$plugin_name"
done

write_ok "configuration symlinks created"

# ========================================================================== #

write_info "installing python3.11.0..."
if pyenv versions --bare | grep "^3\.11\.0$"; then
  write_ok "python3.11.0 already installed, skipping"
else
  pyenv install 3.11.0
fi
write_info "python3.11.0 set as global default"
pyenv global 3.11.0
write_ok "python3.11.0 setup complete"

# ========================================================================== #

write_info "installing nix..."
if command -v nix >/dev/null 2>&1; then
  write_ok "nix is already installed, skipping"
else
  curl \
    --proto '=https' \
    --tlsv1.2 \
    -sSf \
    -L https://install.determinate.systems/nix |
    sh -s -- install --determinate
  write_ok "nix installed"
fi

# ========================================================================== #

write_info "installing claude code..."
if command -v claude >/dev/null 2>&1; then
  write_ok "claude code already installed, skipping"
else
  curl -fsSL https://claude.ai/install.sh | bash
  write_ok "claude code installed"
fi

# ========================================================================== #

write_info "installing pi coding agent..."
if command -v pi >/dev/null 2>&1; then
  write_ok "pi already installed, skipping"
else
  npm install -g @mariozechner/pi-coding-agent
  write_ok "pi installed"
fi

# ========================================================================== #

write_ok "setup for '$hostname' complete!"
write_ok "please reboot your system by running:"
echo
echo "sudo reboot"
echo
