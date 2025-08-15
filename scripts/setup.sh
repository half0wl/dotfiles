#!/bin/bash
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

  # Tools
  "rg"
  "gh"
  "lima"
  "k9s"
  "gcloud-cli"

  # Databases
  "postgresql@17"

  # Languages
  "go"
  "rust"
  "pyenv"
  "nvm"
  "npm"
)

BREW_CASK_DEPS=(
  "orbstack"
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

write_info "Checking Xcode dev tools..."
if xcode-select -p &>/dev/null; then
  write_ok "Xcode dev tools already installed"
else
  write_info "Installing Xcode dev tools..."
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

if [[ -e "${ZDOTDIR:-$HOME}/.zprezto" || -L "${ZDOTDIR:-$HOME}/.zprezto" ]]; then
  write_ok "zprezto already installed, skipping..."
else
  write_info "Installing zprezto..."
  git clone \
    --recursive \
    https://github.com/sorin-ionescu/prezto.git \
    "${ZDOTDIR:-$HOME}/.zprezto"
  write_ok "zprezto installed"
fi
write_info "Changing shell to zsh..."
chsh -s /bin/zsh
write_ok "Shell changed to zsh"

# ========================================================================== #

if command -v brew >/dev/null 2>&1; then
  write_ok "brew already installed, skipping..."
else
  write_info "Installing brew..."
  /bin/bash \
    -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  write_ok "brew installed"
fi

# ========================================================================== #

write_info "Installing brew dependencies..."
printf ' - %s\n' "${BREW_DEPS[@]}"
brew install "${BREW_DEPS[@]}"
write_ok "brew dependencies installed"

# ========================================================================== #

write_info "Installing brew-cask dependencies..."
printf ' - %s\n' "${BREW_CASK_DEPS[@]}"
brew install "${BREW_CASK_DEPS[@]}"
write_ok "brew cask dependencies installed"

# ========================================================================== #

if pyenv versions --bare | grep "^3\.11\.0$"; then
  write_ok "Python 3.11.0 already installed, skipping..."
else
  write_info "Installing Python 3.11.0..."
  pyenv install 3.11.0
fi
write_info "Setting Python 3.11.0 as global default..."
pyenv global 3.11.0
write_ok "Python 3.11.0 setup complete"

# ========================================================================== #

write_info "Setting up directories..."
mkdir -p ~/.cache
mkdir -p ~/.claude
mkdir -p ~/.config
mkdir -p ~/.config/nvim
sudo chown -R $(whoami) ~/.cache
sudo chown -R $(whoami) ~/.claude
sudo chown -R $(whoami) ~/.config
sudo chown -R $(whoami) ~/.config/nvim
write_ok "Directories set up complete"

# ========================================================================== #

write_info "Creating configuration symlinks..."

if [[ -e ~/.zshrc || -L ~/.zshrc ]]; then
  echo "Removing existing ~/.zshrc"
  rm -f ~/.zshrc
fi
ln -s ~/dotfiles/conf/.zshrc ~/.zshrc

if [[ -e ~/.zpreztorc || -L ~/.zpreztorc ]]; then
  echo "Removing existing ~/.zpreztorc"
  rm -f ~/.zpreztorc
fi
ln -s ~/dotfiles/conf/.zpreztorc ~/.zpreztorc

if [[ -e ~/.tmux.conf || -L ~/.tmux.conf ]]; then
  echo "Removing existing ~/.tmux.conf"
  rm -f ~/.tmux.conf
fi
ln -s ~/dotfiles/conf/.tmux.conf ~/.tmux.conf

if [[ -e ~/.config/nvim || -L ~/.config/nvim ]]; then
  echo "Removing existing ~/.config/nvim"
  rm -rf ~/.config/nvim
fi
ln -s ~/dotfiles/nvim ~/.config/nvim

if [[ -e ~/.gitconfig || -L ~/.gitconfig ]]; then
  echo "Removing existing ~/.gitconfig"
  rm -f ~/.gitconfig
fi
ln -s ~/dotfiles/conf/.gitconfig ~/.gitconfig

if [[ -e ~/.gitignore_global || -L ~/.gitignore_global ]]; then
  echo "Removing existing ~/.gitignore_global"
  rm -f ~/.gitignore_global
fi
ln -s ~/dotfiles/conf/.gitignore_global ~/.gitignore_global

if [[ -e ~/.claude/settings.json || -L ~/.claude/settings.json ]]; then
  echo "Removing existing ~/.claude/settings.json"
  rm -f ~/.claude/settings.json
fi
ln -s ~/dotfiles/conf/claude/settings.json ~/.claude/settings.json

GHOSTTY_CONF_PATH="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
if [[ -e "$GHOSTTY_CONF_PATH" || -L "$GHOSTTY_CONF_PATH" ]]; then
  echo "Removing existing $GHOSTTY_CONF_PATH"
  rm -f "$GHOSTTY_CONF_PATH"
fi
ln -s ~/dotfiles/conf/ghostty/config "$GHOSTTY_CONF_PATH"

write_ok "Configuration symlinks successfully created"

# ========================================================================== #

write_info "Installing nix..."
curl \
  --proto '=https' \
  --tlsv1.2 \
  -sSf \
  -L https://install.determinate.systems/nix |
  sh -s -- install --determinate
write_ok "nix installed"
