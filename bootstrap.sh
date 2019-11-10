#!/bin/bash

# Setup symlinks
cd ~/
ln -s ~/dotfiles/.zshrc ~/.zshrc
ln -s ~/dotfiles/.zpreztorc ~/.zpreztorc
ln -s ~/dotfiles/.gitconfig ~/.gitconfig
ln -s ~/dotfiles/.gitignore_global ~/.gitignore_global
ln -s ~/dotfiles/.flake8 ~/.flake8
mkdir -p ~/.ctags.d; ln -s ~/dotfiles/.ctags ~/.ctags.d/default.ctags
