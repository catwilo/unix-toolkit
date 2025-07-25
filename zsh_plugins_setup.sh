#!/usr/bin/env sh
set -eu
d="$HOME/.addons-zsh"
mkdir -p "$d" && cd "$d"
g() { git clone --depth=1 "$1" "$2"; }
g https://github.com/junegunn/fzf fzf
g https://github.com/Aloxaf/fzf-tab fzf-tab
g https://github.com/zsh-users/zsh-autosuggestions zsh-autosuggestions
g https://github.com/zdharma-continuum/fast-syntax-highlighting fast-syntax-highlighting
sudo pacman -S --noconfirm starship || apt install -y starship
