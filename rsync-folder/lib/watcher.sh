#!/usr/bin/env bash
# lib/watcher.sh — hybrid watcher: inotify + poll + heartbeat
# Args: <conf_dir> <profile_name>
#
# Arquitectura de tres capas:
#   Capa 1 — inotifywait/fswatch  : eventos en tiempo real
#   Capa 2 — polling find -newer  : cada POLL_INTERVAL segundos, costo ~0
#   Capa 3 — heartbeat rsync      : cada HEARTBEAT_SEC segundos, garantía absoluta
#
# Debounce reseteable: el timer se reinicia con cada nuevo evento. rsync se
# lanza solo cuando pasan DEBOUNCE_SEC segundos sin actividad. Si un sync ya
# está en curso (flock en sync-runner.sh), el nuevo se marca como pendiente
# y sync-runner lo ejecuta al terminar — nunca se pierden cambios.
#
# Fixes históricos incluidos:
#   - inotifywait se lanzaba dos veces (background huérfano + process substitution)
#   - --no-dereference rompe inotify en symlinks Termux→FUSE
#   - --exclude-from no soportado en build de Termux de inotify-tools
#   - --format no soportado en build de Termux de inotify-tools
#   - Debounce fijo en sync-runner: no agrupaba ráfagas de eventos

# NO usa set -euo pipefail: el loop debe sobrevivir errores de inotifywait/fswatch

CONF_DIR="$1"
PROFILE_NAME="$2"

[[ -z "$CONF_DIR" || -z "$PROFILE_NAME" ]] && {
  printf 'Uso: watcher.sh <conf_dir> <profile_name>\n' >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# ── PID file por perfil ────────────────────────────────────────────────────────
PID_FILE="$CONF_DIR/run/${PROFILE_NAME}.watcher.pid"
mkdir -p "$CONF_DIR/run"
printf '%d' "$$" > "$PID_FILE"

# ── Carga de perfil ────────────────────────────────────────────────────────────
load_profile() {
  local prof_file="$CONF_DIR/profiles/${PROFILE_NAME}.env"
  [[ -f "$prof_file" ]] || {
    log_err "[$PROFILE_NAME] Perfil no encontrado: $prof_file"
    exit 1
  }
  source "$prof_file"
  EXCLUDES_FILE="${EXCLUDES_FILE:-$CONF_DIR/excludes.txt}"
  DIRECTION="${DIRECTION:-push}"
  DEBOUNCE_SEC="${DEBOUNCE_SEC:-2}"
  POLL_INTERVAL="${POLL_INTERVAL:-10}"
  HEARTBEAT_SEC="${HEARTBEAT_SEC:-300}"
}

load_profile

# ── Señales ────────────────────────────────────────────────────────────────────
trap 'load_profile; log_info "[$PROFILE_NAME] Perfil recargado (SIGUSR1)"' SIGUSR1
trap '_watcher_cleanup; exit 0' SIGINT SIGTERM

_watcher_cleanup() {
  log_info "[$PROFILE_NAME] Watcher detenido — limpiando procesos hijos"
  local child
  for child in $(jobs -p 2>/dev/null); do
    kill "$child" 2>/dev/null || true
  done
  rm -f "$PID_FILE"
}

# ── Detección del backend de eventos ──────────────────────────────────────────
_detect_watcher_backend() {
  if command -v inotifywait >/dev/null 2>&1; then
    printf 'inotifywait'
  elif command -v fswatch >/dev/null 2>&1; then
    printf 'fswatch'
  else
    printf 'none'
  fi
}

WATCHER_BACKEND="$(_detect_watcher_backend)"

if [[ "$WATCHER_BACKEND" == "none" ]]; then
  log_warn "[$PROFILE_NAME] inotifywait/fswatch no disponibles — solo polling + heartbeat activos"
else
  log_info "[$PROFILE_NAME] Backend de eventos: $WATCHER_BACKEND"
fi

# ── Debounce reseteable ────────────────────────────────────────────────────────
# Implementado con un archivo timestamp. Cada evento actualiza el archivo.
# Un proceso vigilante compara el timestamp contra DEBOUNCE_SEC y lanza rsync
# solo cuando han pasado DEBOUNCE_SEC segundos sin nuevos eventos.
# Esto agrupa ráfagas (ej: 1000 fotos copiándose) en un único sync.
#
# Flujo:
#   evento → touch DEBOUNCE_FILE
#   vigilante: si (ahora - mtime(DEBOUNCE_FILE)) >= DEBOUNCE_SEC → trigger rsync
#              y borra DEBOUNCE_FILE para no re-disparar

_debounce_watcher() {
  local direction="$1"
  local debounce_file="$CONF_DIR/run/${PROFILE_NAME}.${direction}.debounce"

  log_info "[$PROFILE_NAME/$direction] Vigilante debounce activo (${DEBOUNCE_SEC}s)"

  while true; do
    sleep 0.5

    # Recargar debounce por si cambió el perfil
    local deb="${DEBOUNCE_SEC:-2}"

    [[ -f "$debounce_file" ]] || continue

    # Calcular segundos desde último evento
    local mtime now elapsed
    mtime="$(stat -c '%Y' "$debounce_file" 2>/dev/null)" || continue
    now="$(date +%s)"
    elapsed=$(( now - mtime ))

    if (( elapsed >= deb )); then
      rm -f "$debounce_file"
      log_step "[$PROFILE_NAME/$direction] Debounce cumplido (${elapsed}s) — lanzando sync"
      bash "$SCRIPT_DIR/sync-runner.sh" "$CONF_DIR" "$PROFILE_NAME" "$direction" &
    fi
  done
}

# ── Señal de evento: touch del debounce file ──────────────────────────────────
# Cada capa llama a signal_event en lugar de lanzar rsync directamente.
signal_event() {
  local direction="$1" source="${2:-?}"
  local debounce_file="$CONF_DIR/run/${PROFILE_NAME}.${direction}.debounce"
  touch "$debounce_file"
  log_info "[$PROFILE_NAME/$direction] Evento recibido ($source) — debounce reiniciado"
}

# Versión bloqueante para heartbeat
trigger_sync_wait() {
  local direction="$1"
  log_step "[$PROFILE_NAME/$direction] Heartbeat sync"
  bash "$SCRIPT_DIR/sync-runner.sh" "$CONF_DIR" "$PROFILE_NAME" "$direction"
}

# ── CAPA 1A: Loop con inotifywait ──────────────────────────────────────────────
# Una sola instancia de inotifywait leída con while+read+fd explícito.
# Flags mínimos compatibles con la build recortada de Termux:
#   sin --no-dereference  (rompe inotify en symlinks Termux→FUSE)
#   sin --exclude-from    (no soportado en Termux inotify-tools)
#   sin --format          (no soportado en Termux inotify-tools)
_watch_inotify() {
  local watch_src="$1" direction="$2"
  local backoff=1
  local inotify_pid inotify_fd

  log_info "[$PROFILE_NAME] Capa 1 (inotifywait) activa: $watch_src"

  while true; do
    log_step "[$PROFILE_NAME] inotifywait observando: $watch_src (→$direction)"

    exec {inotify_fd}< <(
      inotifywait \
        -m -q \
        -e close_write,create,delete,moved_to,moved_from,modify \
        "$watch_src" 2>/dev/null
    )
    inotify_pid=$!

    local got_event=0
    while IFS= read -r -u "$inotify_fd" _event; do
      got_event=1
      backoff=1
      signal_event "$direction" "inotify"
    done

    exec {inotify_fd}<&-
    kill "$inotify_pid" 2>/dev/null || true
    wait "$inotify_pid" 2>/dev/null || true

    if [[ $got_event -eq 0 ]]; then
      log_warn "[$PROFILE_NAME] inotifywait salió sin eventos — reiniciando en ${backoff}s"
    else
      log_warn "[$PROFILE_NAME] inotifywait terminó inesperadamente — reiniciando en ${backoff}s"
    fi

    sleep "$backoff"
    (( backoff = backoff < 60 ? backoff * 2 : 60 )) || true
    load_profile
  done
}

# ── CAPA 1B: Loop con fswatch ──────────────────────────────────────────────────
_watch_fswatch() {
  local watch_src="$1" direction="$2"
  local backoff=1

  log_info "[$PROFILE_NAME] Capa 1 (fswatch) activa: $watch_src"

  while true; do
    log_step "[$PROFILE_NAME] fswatch observando: $watch_src (→$direction)"

    local exclude_args=()
    if [[ -f "$EXCLUDES_FILE" ]]; then
      while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        exclude_args+=("--exclude" "$pattern")
      done < "$EXCLUDES_FILE"
    fi

    local got_event=0
    while IFS= read -r _event; do
      got_event=1
      backoff=1
      signal_event "$direction" "fswatch"
    done < <(
      fswatch \
        --recursive \
        --event Created --event Updated --event Removed \
        --event Renamed --event MovedFrom --event MovedTo \
        "${exclude_args[@]}" \
        --one-per-batch \
        "$watch_src" 2>/dev/null
    )

    log_warn "[$PROFILE_NAME] fswatch terminó — reiniciando en ${backoff}s"
    sleep "$backoff"
    (( backoff = backoff < 60 ? backoff * 2 : 60 )) || true
    load_profile
  done
}

# ── CAPA 2: Polling con find -newer ───────────────────────────────────────────
# Costo real en Downloads con ~1000 archivos: <5ms por pasada.
# Solo señala evento si detecta archivos más nuevos que el último stamp.
_watch_poll() {
  local watch_src="$1" direction="$2" interval="$3"
  local stamp_file="$CONF_DIR/run/${PROFILE_NAME}.${direction}.poll_stamp"

  log_info "[$PROFILE_NAME] Capa 2 (poll find -newer) activa: cada ${interval}s"

  touch "$stamp_file"

  while true; do
    sleep "$interval"
    interval="${POLL_INTERVAL:-$interval}"

    local changed
    changed="$(find "$watch_src" -newer "$stamp_file" \
      -not -path '*/.rsync-backup/*' 2>/dev/null | head -1)"

    touch "$stamp_file"

    if [[ -n "$changed" ]]; then
      log_info "[$PROFILE_NAME] Poll detectó cambio: $changed"
      signal_event "$direction" "poll"
    fi
  done
}

# ── CAPA 3: Heartbeat ─────────────────────────────────────────────────────────
# Sync forzado periódico — garantía absoluta de consistencia.
# Corre el primer sync al arrancar para resolver archivos preexistentes.
_watch_heartbeat() {
  local direction="$1" interval="$2"

  log_info "[$PROFILE_NAME] Capa 3 (heartbeat) activa: cada ${interval}s"

  log_step "[$PROFILE_NAME] Sync inicial al arrancar"
  trigger_sync_wait "$direction" || true

  while true; do
    sleep "$interval"
    interval="${HEARTBEAT_SEC:-$interval}"
    trigger_sync_wait "$direction" || true
  done
}

# ── Dispatcher por DIRECTION ───────────────────────────────────────────────────
_start_watchers() {
  local src="$1" direction="$2"

  # Vigilante debounce — siempre activo, en background
  _debounce_watcher "$direction" &

  # Capa 1 — eventos en tiempo real (background)
  case "$WATCHER_BACKEND" in
    inotifywait) _watch_inotify "$src" "$direction" & ;;
    fswatch)     _watch_fswatch "$src" "$direction" & ;;
    *)           log_warn "[$PROFILE_NAME/$direction] Sin capa 1 — solo poll + heartbeat" ;;
  esac

  # Capa 2 — polling (background)
  _watch_poll "$src" "$direction" "${POLL_INTERVAL:-10}" &

  # Capa 3 — heartbeat (foreground: mantiene vivo el subshell de dirección)
  _watch_heartbeat "$direction" "${HEARTBEAT_SEC:-300}"
}

# ── Arranque ───────────────────────────────────────────────────────────────────
log_sep "rsync-folder watcher — $PROFILE_NAME"
log_kv "Fuente"      "$SOURCE"
log_kv "Destino"     "$DESTINATION"
log_kv "Dirección"   "$DIRECTION"
log_kv "Debounce"    "${DEBOUNCE_SEC:-2}s (reseteable)"
log_kv "Poll"        "${POLL_INTERVAL:-10}s"
log_kv "Heartbeat"   "${HEARTBEAT_SEC:-300}s"
log_kv "Backend"     "$WATCHER_BACKEND"

case "$DIRECTION" in
  push)
    _start_watchers "$SOURCE" push
    ;;
  pull)
    _start_watchers "$DESTINATION" pull
    ;;
  both)
    _start_watchers "$SOURCE"      push &
    _PUSH_PID=$!
    _start_watchers "$DESTINATION" pull &
    _PULL_PID=$!
    wait "$_PUSH_PID" "$_PULL_PID"
    ;;
  *)
    log_err "[$PROFILE_NAME] DIRECTION inválido: '$DIRECTION' (push|pull|both)"
    rm -f "$PID_FILE"
    exit 1
    ;;
esac
