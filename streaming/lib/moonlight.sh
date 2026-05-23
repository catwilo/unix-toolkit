#!/usr/bin/env bash
# =============================================================================
# lib/moonlight.sh — Gestión del proceso Moonlight Qt
#
# Variables requeridas:
#   MOONLIGHT_BIN, MOONLIGHT_LOG
#   SUNSHINE_HOST  (vacío = descubrimiento mDNS)
# =============================================================================

# ── moonlight_running ─────────────────────────────────────────────────────────
moonlight_running() {
    pgrep -x moonlight-qt &>/dev/null
}

# ── preflight_moonlight ───────────────────────────────────────────────────────
preflight_moonlight() {
    local ok=0

    command -v "$MOONLIGHT_BIN" &>/dev/null \
        || { warn "'${MOONLIGHT_BIN}' no encontrado. ¿Ejecutaste setup.sh moonlight?"; ok=1; }

    for grp in video input; do
        id -nG "$USER" | grep -qw "$grp" \
            || warn "Usuario no está en grupo '${grp}'. ¿Reiniciaste tras el setup?"
    done

    [[ -e /dev/dri/card0 ]] \
        && ok "GPU disponible: /dev/dri/card0" \
        || warn "/dev/dri/card0 no existe — decodificación por CPU."

    if [[ -n "${DISPLAY:-}" ]]; then
        ok "Backend gráfico: X11 (${DISPLAY})"
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        ok "Backend gráfico: Wayland (${WAYLAND_DISPLAY})"
    else
        warn "Sin sesión gráfica detectada — Moonlight intentará modo KMS/DRM."
    fi

    return $ok
}

# ── check_connectivity ────────────────────────────────────────────────────────
check_connectivity() {
    if [[ -z "${SUNSHINE_HOST:-}" ]]; then
        log "SUNSHINE_HOST vacío — descubrimiento automático vía mDNS."
        return 0
    fi

    ping -c 1 -W 2 "$SUNSHINE_HOST" &>/dev/null \
        && ok "Servidor alcanzable: ${SUNSHINE_HOST}" \
        || warn "No se pudo hacer ping a ${SUNSHINE_HOST}."

    if command -v nc &>/dev/null; then
        nc -z -w 3 "$SUNSHINE_HOST" 47989 2>/dev/null \
            && ok "Puerto 47989 abierto en ${SUNSHINE_HOST}" \
            || warn "Puerto 47989 no responde — ¿corre run_sunshine.sh en el servidor?"
    fi
}

# ── start_moonlight ───────────────────────────────────────────────────────────
start_moonlight() {
    if moonlight_running; then
        local _ml_pid; _ml_pid=$(pgrep -x moonlight-qt 2>/dev/null | head -1 || true)
        warn "Moonlight ya está corriendo (PID ${_ml_pid})."
        warn "Cerrando instancia previa..."
        stop_moonlight
        sleep 1
    fi

    local cmd
    if [[ -n "${SUNSHINE_HOST:-}" ]]; then
        cmd="$MOONLIGHT_BIN stream $SUNSHINE_HOST"
    else
        cmd="$MOONLIGHT_BIN"
    fi

    log "Lanzando: ${cmd}"
    $cmd >> "$MOONLIGHT_LOG" 2>&1 &
    local pid=$!
    sleep 2

    kill -0 "$pid" 2>/dev/null || {
        warn "Moonlight terminó inmediatamente. Últimas líneas del log:"
        tail -8 "$MOONLIGHT_LOG" 2>/dev/null || true
        fail "Moonlight no arrancó. Ver: ${MOONLIGHT_LOG}"
    }

    ok "Moonlight Qt activo (PID: ${pid})"
}

# ── stop_moonlight ────────────────────────────────────────────────────────────
stop_moonlight() {
    if ! moonlight_running; then
        log "Moonlight no está corriendo."
        return 0
    fi
    log "Deteniendo Moonlight..."
    pkill -TERM moonlight-qt 2>/dev/null || true
    sleep 2
    moonlight_running && { pkill -KILL moonlight-qt 2>/dev/null || true; sleep 1; }
    ok "Moonlight detenido."
}
