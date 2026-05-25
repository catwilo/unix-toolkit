# mpd.sh — optional MPD setup for Termux
# Requires: core.sh, detect.sh (PLATFORM set via init_platform)

MPD_MUSIC_DIR="${MPD_MUSIC_DIR:-/storage/8177-8535/music}"

setup_mpd() {
  [ "$PLATFORM" = "termux" ] || { info "MPD: solo Termux, omitiendo"; return 0; }
  step "Configurando MPD"

  run mkdir -p \
    "$HOME/.local/share/mpd/playlists" \
    "$HOME/.config/mpd" \
    "$HOME/.cache/mpd"

  local conf="$HOME/.config/mpd/mpd.conf"
  if [ -f "$conf" ] && ! [ -L "$conf" ]; then
    warn "mpd.conf existe como archivo suelto — usando el del repo via symlink"
  fi

  # Config comes from custom_termux symlink (link_dotfiles handles it)
  # Only start services here
  run pulseaudio --start --exit-idle-time=-1 2>/dev/null || warn "PulseAudio ya activo o no disponible"
  pkill mpd 2>/dev/null || true
  run mpd "$HOME/.config/mpd/mpd.conf" || warn "MPD no pudo iniciarse"
  run mpc -h 127.0.0.1 -p 6600 update || warn "mpc update falló"
  ok "MPD listo"
}
