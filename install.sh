#!/bin/bash

# zprezto
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
chsh -s /bin/zsh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# brew
brew install tmux
brew install neovim
brew install coreutils
brew install wget
brew install rg
brew install direnv
brew install pyenv
brew install rust
brew install go
brew install nvm
brew install gh
brew install lima
brew install gcloud-cli
brew install postgresql@17

# brew casks
brew install --cask font-monaspace
brew install --cask orbstack

# setup symlinks
cd ~/
sudo chown -R $(whoami) ~/.cache
ln -s ~/dotfiles/.zshrc ~/.zshrc
ln -s ~/dotfiles/.zpreztorc ~/.zpreztorc
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
ln -s ~/dotfiles/.gitignore_global ~/.gitignore_global
ln -s ~/dotfiles/.flake8 ~/.flake8
ln -s ~/dotfiles/.tmux.conf ~/.tmux.conf
mkdir -p ~/.config
ln -s ~/dotfiles/nvim ~/.config/nvim
mkdir -p ~/.claude
ln -s ~/dotfiles/claude-settings.json ~/.claude/settings.json

# nix
NIX_INSTALLER="$HOME/Downloads/detsys-install.nix.pkg"
wget -O "$NIX_INSTALLER" https://install.determinate.systems/determinate-pkg/stable/Universal
open -a Installer "$NIX_INSTALLER"
