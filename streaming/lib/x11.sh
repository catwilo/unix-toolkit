#!/usr/bin/env bash
# =============================================================================
# lib/x11.sh — Gestión de sesión X11
#
# Contratos:
#   ensure_x11   → inicia Xorg SI no está corriendo en DISPLAY_NUM.
#                  Si ya corre: retorna 0 sin tocar nada.
#                  Si arranca: espera hasta que xrandr responda.
#                  Si falla N veces: retorna 1 (el watchdog decide qué hacer).
#   stop_x11     → mata Xorg limpiamente. Solo llamar desde stop --force o
#                  watchdog cuando Xorg está caído y hay que reiniciarlo.
#
# Variables requeridas (deben estar en entorno del caller):
#   DISPLAY_NUM   (ej: ":0")
#   VT_NUM        (ej: "vt1")
#   XORG_LOG      (ej: "/tmp/xorg_sunshine.log")
#   REAL_USER, REAL_HOME
#   XORG_WAIT_SEC, XORG_RETRY_MAX
# =============================================================================

# ── Verificar que Xorg responde en DISPLAY_NUM ────────────────────────────────
# Retorna 0 si xrandr ok, 1 si no.
_x11_responsive() {
    DISPLAY="$DISPLAY_NUM" XAUTHORITY="$REAL_HOME/.Xauthority" \
        xrandr &>/dev/null
}

# ── Verificar que el proceso Xorg existe en el display correcto ───────────────
# Considera que puede haber Xorg en otro display — solo nos importa el nuestro.
_x11_running() {
    # Buscar el lock file del display
    local lock="/tmp/.X${DISPLAY_NUM#:}-lock"
    if [[ -f "$lock" ]]; then
        local pid
        pid=$(cat "$lock" 2>/dev/null | tr -d ' ' || echo "0")
        [[ "$pid" -gt 0 ]] && kill -0 "$pid" 2>/dev/null
    else
        return 1
    fi
}

# ── ensure_x11 ────────────────────────────────────────────────────────────────
ensure_x11() {
    # Si ya está corriendo y responde: OK inmediato.
    if _x11_running && _x11_responsive; then
        ok "X11 ya activo en ${DISPLAY_NUM} — reutilizando."
        export DISPLAY="$DISPLAY_NUM"
        export XAUTHORITY="$REAL_HOME/.Xauthority"
        return 0
    fi

    # Si hay lock huérfano: limpiarlo antes de arrancar.
    local lock="/tmp/.X${DISPLAY_NUM#:}-lock"
    if [[ -f "$lock" ]]; then
        local pid
        pid=$(cat "$lock" 2>/dev/null | tr -d ' ' || echo "0")
        if [[ "$pid" -gt 0 ]] && kill -0 "$pid" 2>/dev/null; then
            warn "Xorg (PID $pid) existe pero no responde — terminando..."
            sudo kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            kill -0 "$pid" 2>/dev/null && { sudo kill -KILL "$pid" 2>/dev/null || true; sleep 1; }
        fi
        sudo rm -f "$lock"
    fi

    # Limpiar Xauthority si el owner no es el usuario correcto.
    local xauth="$REAL_HOME/.Xauthority"
    if [[ -f "$xauth" ]]; then
        local owner
        owner=$(stat -c '%U' "$xauth" 2>/dev/null || echo "unknown")
        [[ "$owner" != "$REAL_USER" ]] && sudo rm -f "$xauth"
    fi
    touch "$xauth"

    log "Iniciando Xorg en ${DISPLAY_NUM} (${VT_NUM})..."
    sudo Xorg "$DISPLAY_NUM" -noreset -nolisten tcp \
        -logfile "$XORG_LOG" "$VT_NUM" &>/dev/null &

    export DISPLAY="$DISPLAY_NUM"
    export XAUTHORITY="$xauth"

    # Espera inicial configurable.
    sleep "$XORG_WAIT_SEC"
    sudo chmod 644 "$XORG_LOG" 2>/dev/null || true

    # Poll hasta que xrandr responda.
    local attempt=0
    until _x11_responsive; do
        attempt=$((attempt + 1))
        if (( attempt >= XORG_RETRY_MAX )); then
            warn "Xorg no responde tras ${XORG_RETRY_MAX} intentos. Ver: ${XORG_LOG}"
            return 1
        fi
        warn "Esperando Xorg... (${attempt}/${XORG_RETRY_MAX})"
        sleep 2
    done

    # Permisos de acceso local.
    xhost +local: &>/dev/null || true
    local xorg_pid; xorg_pid=$(pgrep -x Xorg 2>/dev/null | head -1 || true)
    ok "Xorg activo en ${DISPLAY_NUM} (PID ${xorg_pid})."
    return 0
}

# ── stop_x11 ─────────────────────────────────────────────────────────────────
# Mata Xorg limpiamente. Idempotente — si no corre, retorna 0.
stop_x11() {
    local lock="/tmp/.X${DISPLAY_NUM#:}-lock"
    if ! _x11_running; then
        log "Xorg no está corriendo — nada que detener."
        return 0
    fi
    log "Deteniendo Xorg..."
    sudo pkill -TERM Xorg 2>/dev/null || true
    sleep 2
    _x11_running && { sudo pkill -KILL Xorg 2>/dev/null || true; sleep 1; }
    sudo rm -f "$lock"
    ok "Xorg detenido."
}

# ── vaapi_check ───────────────────────────────────────────────────────────────
# Exporta vars VAAPI y muestra estado. No fatal si falla.
vaapi_setup() {
    export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}"
    export LIBVA_DRIVERS_PATH="${LIBVA_DRIVERS_PATH:-/usr/lib/x86_64-linux-gnu/dri}"
    xhost +local: &>/dev/null || true

    local out
    out=$(vainfo 2>&1 || true)
    if echo "$out" | grep -qi "error\|failed\|cannot"; then
        warn "VAAPI con problemas — Sunshine usará CPU como fallback."
    else
        local h264 hevc
        h264=$(echo "$out" | grep -c "H264\|AVC"  || true)
        hevc=$(echo "$out" | grep -c "HEVC\|H265" || true)
        ok "VAAPI funcional — H.264: ${h264} perfiles | HEVC: ${hevc} perfiles"
    fi
}
