# mpd.sh — MPD setup: Termux (PulseAudio) + Debian/Raspbian headless (ALSA)
# Requires: core.sh, detect.sh (PLATFORM set via init_platform)

_mpd_ask_music_dir() {
  local default="$1"
  printf "
  Directorio de música [%s]: " "$default"
  read -r input
  echo "${input:-$default}"
}

_mpd_write_conf() {
  local music_dir="$1"
  local audio_block="$2"
  local conf="$HOME/.config/mpd/mpd.conf"
  run mkdir -p "$HOME/.local/share/mpd/playlists" "$HOME/.config/mpd" "$HOME/.cache/mpd"
  if [ "$DRY_RUN" = "1" ]; then
    info "[dry] escribiría mpd.conf con music_directory=$music_dir"
    return 0
  fi
  cat > "$conf" << MPDCONF
music_directory     "$music_dir"
playlist_directory  "$HOME/.local/share/mpd/playlists"
db_file             "$HOME/.local/share/mpd/database"
log_file            "$HOME/.local/share/mpd/log"
pid_file            "$HOME/.local/share/mpd/pid"
state_file          "$HOME/.local/share/mpd/state"
bind_to_address     "127.0.0.1"
port                "6600"
connection_timeout  "5"

$audio_block
MPDCONF
  ok "mpd.conf escrito"
}

_mpd_termux() {
  local default_dir="/storage/emulated/0/Music"
  local music_dir
  music_dir="$(_mpd_ask_music_dir "$default_dir")"
  local audio_block="audio_output {
    type "pulse"
    name "Android PulseAudio"
}"
  _mpd_write_conf "$music_dir" "$audio_block"
  run pulseaudio --start --exit-idle-time=-1 2>/dev/null || warn "PulseAudio ya activo o no disponible"
  pkill mpd 2>/dev/null || true
  run mpd "$HOME/.config/mpd/mpd.conf" || warn "MPD no pudo iniciarse"
  run mpc -h 127.0.0.1 -p 6600 update || warn "mpc update falló"
}

_mpd_debian() {
  local default_dir="$HOME/music"
  local music_dir
  music_dir="$(_mpd_ask_music_dir "$default_dir")"
  local audio_block="audio_output {
    type "alsa"
    name "ALSA"
}"
  _mpd_write_conf "$music_dir" "$audio_block"
  pkill mpd 2>/dev/null || true
  run mpd "$HOME/.config/mpd/mpd.conf" || warn "MPD no pudo iniciarse"
  run mpc -h 127.0.0.1 -p 6600 update || warn "mpc update falló"
}

setup_mpd() {
  step "Configurando MPD"
  case "$PLATFORM" in
    termux) _mpd_termux ;;
    debian) _mpd_debian ;;
    *) warn "MPD: plataforma no soportada, omitiendo" ;;
  esac
  ok "MPD listo"
}
