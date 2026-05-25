# links.sh — symlink dotfiles from CUSTOM_TERMUX_DIR to $HOME
# Requires: core.sh

CUSTOM_TERMUX_DIR="${CUSTOM_TERMUX_DIR:-$HOME/custom_termux}"

# ── Single symlink ────────────────────────────────────────────────────────────
link_file() {
  local rel="$1"
  local src="$CUSTOM_TERMUX_DIR/$rel"
  local dst="$HOME/$rel"
  [ -e "$src" ] || { warn "no existe en repo: $rel"; return 0; }
  run mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    run rm "$dst"
  elif [ -e "$dst" ]; then
    run mv "$dst" "${dst}.bak"
    warn "backup: ${dst}.bak"
  fi
  run ln -s "$src" "$dst"
  ok "$dst → $src"
}

# ── All dotfiles ──────────────────────────────────────────────────────────────
link_dotfiles() {
  step "Enlazando dotfiles"
  link_file ".zshrc"
  link_file ".zprofile"
  link_file ".addons-zsh"
  link_file ".config/starship.toml"
  link_file ".config/byobu"
  link_file ".config/nvim"
  link_file ".config/ranger"
  link_file ".config/mpd"
  link_file ".config/ncmpcpp"
  link_file ".termux/colors.properties"
  link_file ".termux/font.ttf"
  link_file ".termux/termux.properties"
}
