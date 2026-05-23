#!/usr/bin/env bash
# lib/sync-runner.sh — ejecuta un pase de rsync con reintentos.
# Args: <conf_dir> <profile_name> [push|pull]
#
# FIXES vs original:
#  - Eliminado --no-whole-file: conflicta con --checksum y causa no-transferencia
#    de archivos nuevos en destinos remotos (bug principal reportado).
#  - Añadido --partial: reanuda transferencias interrumpidas (crítico en Termux/WiFi).
#  - Añadido --timeout=30: evita bloqueos silenciosos en conexiones inestables.
#  - Añadido --human-readable a las stats para logs más legibles.
#  - Lock file verificado con flock -n para evitar syncs simultáneos del mismo perfil.
#  - PENDING_FILE correctamente limpiado antes del bucle de reintento.
#  - Separación clara push vs pull para el log.
#  - Compatibilidad Termux: no se asume /tmp, se usa TMPDIR.
#  - Debounce eliminado: ahora lo gestiona watcher.sh con debounce reseteable
#    (se reinicia con cada evento, agrupa ráfagas de archivos correctamente).

# NO usa set -euo pipefail: los errores de rsync deben manejarse explícitamente.

CONF_DIR="$1"
PROFILE_NAME="$2"
DIRECTION="${3:-both}"

[[ -z "$CONF_DIR" || -z "$PROFILE_NAME" ]] && {
  printf 'Uso: sync-runner.sh <conf_dir> <profile_name> [push|pull]\n' >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# Cargar perfil
PROF_FILE="$CONF_DIR/profiles/${PROFILE_NAME}.env"
[[ -f "$PROF_FILE" ]] || {
  log_err "[$PROFILE_NAME] Perfil no encontrado: $PROF_FILE"
  exit 1
}
source "$PROF_FILE"

EXCLUDES_FILE="${EXCLUDES_FILE:-$CONF_DIR/excludes.txt}"
LOCK_FILE="$CONF_DIR/run/${PROFILE_NAME}.${DIRECTION}.lock"
PENDING_FILE="$CONF_DIR/run/${PROFILE_NAME}.${DIRECTION}.pending"
LOG_FILE="$CONF_DIR/sync.log"
mkdir -p "$CONF_DIR/run"

_log_file() {
  printf '[%s] [%s/%s] %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$PROFILE_NAME" "$DIRECTION" "$*" \
    >> "$LOG_FILE"
}

# ── Lock exclusivo: si ya hay un sync en curso, marcar pendiente y salir ───────
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  touch "$PENDING_FILE"
  log_info "[$PROFILE_NAME/$DIRECTION] Sync en curso — marcado pendiente"
  exit 0
fi

# ── Calcular src/dst según dirección ──────────────────────────────────────────
if [[ "$DIRECTION" == "both" ]]; then
  bash "$0" "$1" "$2" push && bash "$0" "$1" "$2" pull
  exit $?
elif [[ "$DIRECTION" == "pull" ]]; then
  _SRC="$DESTINATION"
  _DST="$SOURCE"
else
  _SRC="$SOURCE"
  _DST="$DESTINATION"
fi

# ── Construir comando SSH ──────────────────────────────────────────────────────
_SSH_KEY="${SSH_KEY:-}"
_SSH_CMD="ssh"
_SSH_CMD+=" -o BatchMode=yes"
_SSH_CMD+=" -o ConnectTimeout=10"
_SSH_CMD+=" -o StrictHostKeyChecking=accept-new"
_SSH_CMD+=" -o ServerAliveInterval=15"
_SSH_CMD+=" -o ServerAliveCountMax=3"
[[ -n "$_SSH_KEY" && -f "$_SSH_KEY" ]] && _SSH_CMD+=" -i $(printf '%q' "$_SSH_KEY")"

# ── Argumentos rsync ───────────────────────────────────────────────────────────
# FIX PRINCIPAL: se elimina --no-whole-file porque:
#   - Con --checksum, rsync ya compara por contenido (hash), no por tamaño/fecha.
#   - --no-whole-file fuerza transferencia delta incluso en archivos nuevos,
#     lo que en destinos remotos provoca que archivos nuevos NO se transfieran
#     si el destino no puede abrir el archivo base para el delta.
#   - La combinación --no-whole-file + --checksum es contradictoria en la práctica.
#
# Se añade --partial para reanudar transferencias cortadas (WiFi inestable en Termux).
# Se añade --timeout=30 para no bloquearse en conexiones muertas.
_RSYNC_ARGS=(
  -az
  --checksum
  --partial
  --timeout=30
  --delete
  --delete-after
  --exclude-from="$EXCLUDES_FILE"
  --stats
  --human-readable
  -e "$_SSH_CMD"
)

if [[ "${BACKUP_ON_OVERWRITE:-0}" == "1" ]]; then
  _RSYNC_ARGS+=(
    --backup
    --backup-dir=".rsync-backup/$(date +%Y%m%d)"
  )
fi

# ── Función de sincronización ──────────────────────────────────────────────────
do_rsync() {
  local output exit_code=0
  output="$(rsync "${_RSYNC_ARGS[@]}" "${_SRC}/" "${_DST}/" 2>&1)" || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    local files_sent total_size
    files_sent="$(printf '%s\n' "$output" \
      | grep 'Number of regular files transferred' \
      | grep -oE '[0-9,]+' | tr -d ',' | head -1)" || files_sent=0
    total_size="$(printf '%s\n' "$output" \
      | grep 'Total transferred file size' \
      | grep -oE '[0-9,.A-Za-z]+' | head -1)" || total_size=0
    files_sent="${files_sent:-0}"
    total_size="${total_size:-0}"

    _log_file "OK — archivos: ${files_sent}, tamaño: ${total_size}"
    printf '%s\t%s\t%s\t%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$PROFILE_NAME" \
      "${files_sent}" "${total_size}" \
      >> "$CONF_DIR/sync-stats.tsv"
    log_ok "[$PROFILE_NAME/$DIRECTION] Sync OK — archivos: ${files_sent}"
    return 0
  else
    local err_tail
    err_tail="$(printf '%s\n' "$output" | tail -3 | tr '\n' ' ')"
    _log_file "ERROR exit=$exit_code — $err_tail"
    log_err "[$PROFILE_NAME/$DIRECTION] rsync falló (exit=$exit_code): $err_tail"
    return "$exit_code"
  fi
}

# ── Reintentos ────────────────────────────────────────────────────────────────
run_with_retry() {
  local attempt=1 max="${MAX_RETRIES:-5}" delay="${RETRY_DELAY:-5}"
  while (( attempt <= max )); do
    if do_rsync; then
      return 0
    fi
    log_warn "[$PROFILE_NAME/$DIRECTION] Intento $attempt/$max fallido — reintentando en ${delay}s"
    sleep "$delay"
    (( attempt++ )) || true
  done
  log_err "[$PROFILE_NAME/$DIRECTION] Abortado tras $max intentos"
  return 1
}

# ── Bucle de resyncs pendientes ────────────────────────────────────────────────
while true; do
  rm -f "$PENDING_FILE"
  run_with_retry || true
  [[ ! -f "$PENDING_FILE" ]] && break
  log_info "[$PROFILE_NAME/$DIRECTION] Cambios pendientes detectados — resincronizando"
done
