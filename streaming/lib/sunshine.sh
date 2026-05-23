#!/usr/bin/env bash
# =============================================================================
# lib/sunshine.sh — Gestión del proceso Sunshine
#
# Contratos:
#   start_sunshine   → lanza Sunshine en background. Si ya corre: warn + return 1.
#   stop_sunshine    → TERM → KILL. No toca Xorg ni byobu.
#   restart_sunshine → stop_sunshine + start_sunshine.
#   sunshine_running → retorna 0 si el proceso existe, 1 si no.
#
# Variables requeridas:
#   SUNSHINE_BIN, SUNSHINE_LOG
#   DISPLAY_NUM, REAL_HOME
#   LIBVA_DRIVER_NAME, LIBVA_DRIVERS_PATH
#   PANE_SUNSHINE  (pane-id real del pane de sunshine, si hay ventana byobu)
# =============================================================================

# ── sunshine_running ─────────────────────────────────────────────────────────
sunshine_running() {
    pgrep -x sunshine &>/dev/null
}

# ── _sunshine_env ─────────────────────────────────────────────────────────────
# Exporta env necesario para Sunshine.
_sunshine_env() {
    export DISPLAY="${DISPLAY_NUM}"
    export XAUTHORITY="${REAL_HOME}/.Xauthority"
    export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}"
    export LIBVA_DRIVERS_PATH="${LIBVA_DRIVERS_PATH:-/usr/lib/x86_64-linux-gnu/dri}"
}

# ── start_sunshine ────────────────────────────────────────────────────────────
# Si hay sesión byobu activa, lanza dentro del pane dedicado.
# Si no, lanza en background directo.
start_sunshine() {
    if sunshine_running; then
        local _sun_pid; _sun_pid=$(pgrep -x sunshine 2>/dev/null | head -1 || true)
        warn "Sunshine ya está corriendo (PID ${_sun_pid}) — nada que hacer."
        return 1
    fi

    _sunshine_env

    local env_str
    env_str="export DISPLAY=${DISPLAY_NUM}; export XAUTHORITY=${REAL_HOME}/.Xauthority; \
export LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME}; export LIBVA_DRIVERS_PATH=${LIBVA_DRIVERS_PATH}"

    if [[ -n "${PANE_SUNSHINE:-}" ]] && byobu list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$PANE_SUNSHINE"; then
        log "Lanzando Sunshine en pane byobu [${PANE_SUNSHINE}]..."
        byobu send-keys -t "$PANE_SUNSHINE" \
            "${env_str}; echo '[sunshine] Arrancando...'; ${SUNSHINE_BIN} 2>&1 | tee -a ${SUNSHINE_LOG}" \
            Enter 2>/dev/null || true
    else
        log "Lanzando Sunshine en background..."
        ( _sunshine_env; exec "$SUNSHINE_BIN" >> "$SUNSHINE_LOG" 2>&1 ) &
    fi

    # Espera breve y verifica.
    local i
    for i in 1 2 3; do
        sleep 2
        sunshine_running && {
            local _pid; _pid=$(pgrep -x sunshine 2>/dev/null | head -1 || true)
            ok "Sunshine activo (PID ${_pid})."
            return 0
        }
    done

    warn "Sunshine no arrancó tras 6s. Ver: ${SUNSHINE_LOG}"
    return 1
}

# ── stop_sunshine ─────────────────────────────────────────────────────────────
# No toca Xorg, i3 ni byobu.
stop_sunshine() {
    if ! sunshine_running; then
        log "Sunshine no está corriendo."
        return 0
    fi
    log "Deteniendo Sunshine..."
    pkill -TERM sunshine 2>/dev/null || true
    sleep 2
    sunshine_running && { pkill -KILL sunshine 2>/dev/null || true; sleep 1; }
    sunshine_running \
        && { warn "Sunshine no se detuvo — revisar manualmente."; return 1; } \
        || ok "Sunshine detenido."
}

# ── restart_sunshine ──────────────────────────────────────────────────────────
# Solo Sunshine. Xorg/i3/byobu intocables.
restart_sunshine() {
    log "Reiniciando Sunshine (solo Sunshine)..."
    stop_sunshine
    sleep 1
    start_sunshine
}
