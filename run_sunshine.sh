#!/usr/bin/env bash
# =============================================================================
# run_sunshine.sh — Sunshine headless con watchdog y byobu multipanel
# Versión: 8.0-PROD
#
# Arquitectura byobu (1 sesión, 1 ventana, 4 panes):
#
#   Sesión: "sunshine"
#   └── Ventana 0: "monitor"
#       ├── pane 0 [xorg]      → top-left   : tail -f xorg log
#       ├── pane 1 [i3]        → top-center : output de i3
#       ├── pane 2 [sunshine]  → top-right  : output de Sunshine
#       └── pane 3 [watchdog]  → bottom     : monitor de salud (ancho completo)
#
# ┌─────────────┬─────────────┬─────────────┐
# │  xorg log   │     i3      │   sunshine  │
# ├─────────────┴─────────────┴─────────────┤
# │              watchdog (grande)          │
# └─────────────────────────────────────────┘
#
# Uso:
#   ./run_sunshine.sh start    ← arranca todo, devuelve prompt
#   ./run_sunshine.sh stop     ← apaga todo limpiamente
#   ./run_sunshine.sh restart  ← stop + start en un solo paso
#   ./run_sunshine.sh status   ← estado de los procesos
#   ./run_sunshine.sh logs [sunshine|xorg|i3|watchdog]
#
# Para ver el panel de monitoreo:
#   byobu attach-session -t sunshine
#
# ⚠ Ejecutar como usuario normal, NUNCA como root.
# =============================================================================
set -euo pipefail

# ─── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Configuración ────────────────────────────────────────────────────────────
DISPLAY_NUM=":0"
VT_NUM="vt1"
XORG_LOG="/tmp/xorg_sunshine.log"
SUNSHINE_LOG="/tmp/sunshine_run.log"
I3_LOG="/tmp/i3_sunshine.log"
WATCHDOG_LOG="/tmp/sunshine_watchdog.log"
XORG_WAIT_SEC=5
XORG_RETRY_MAX=10
SUNSHINE_BIN="sunshine"
WATCHDOG_INTERVAL=7
WATCHDOG_BACKOFF_MAX=21
PID_FILE="/tmp/sunshine_watchdog.pid"
BYOBU_SESSION="sunshine"
BYOBU_WINDOW="monitor"

# Porcentaje de altura para el pane watchdog (del total de filas de la terminal)
WATCHDOG_PANE_PERCENT=40

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo -e "${CYAN}[INFO]${RESET}  $(date '+%H:%M:%S') $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $(date '+%H:%M:%S') $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $(date '+%H:%M:%S') $*"; }
fail() { echo -e "${RED}[ERROR]${RESET} $(date '+%H:%M:%S') $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && fail "NO ejecutes como root. Usa tu usuario normal."

REAL_USER="$USER"
REAL_HOME="$HOME"

# =============================================================================
# LIMPIEZA TOTAL DE SESIÓN BYOBU/TMUX
# Destruye la sesión "sunshine" si existe, sin afectar otras sesiones del usuario.
# =============================================================================
_kill_byobu_session() {
    if byobu has-session -t "$BYOBU_SESSION" 2>/dev/null; then
        log "Sesión byobu '$BYOBU_SESSION' detectada — eliminando..."
        byobu kill-session -t "$BYOBU_SESSION" 2>/dev/null || true
        sleep 1
        # Verificar que desapareció
        if byobu has-session -t "$BYOBU_SESSION" 2>/dev/null; then
            warn "No se pudo eliminar la sesión '$BYOBU_SESSION' limpiamente. Forzando..."
            tmux kill-session -t "$BYOBU_SESSION" 2>/dev/null || true
        fi
        ok "Sesión '$BYOBU_SESSION' eliminada."
    fi
}

# =============================================================================
# CMD_START
# =============================================================================
cmd_start() {

    # ── Guardia watchdog previo ────────────────────────────────────────────────
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "Watchdog ya corriendo (PID $(cat "$PID_FILE")). Usa '$0 stop' primero."
        exit 1
    fi

    # ── Limpiar sesión byobu anterior SIEMPRE (evita "index N in use") ─────────
    _kill_byobu_session

    # ── Verificar dependencias ─────────────────────────────────────────────────
    for bin in xrandr vainfo sudo byobu tmux i3; do
        command -v "$bin" &>/dev/null \
            || fail "Binario no encontrado: '$bin'. Instálalo primero."
    done
    for grp in video render input; do
        id -nG "$REAL_USER" | grep -qw "$grp" \
            || warn "Usuario no está en grupo '$grp'. ¿Reiniciaste tras el setup?"
    done

    echo -e "\n${BOLD}══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Sunshine Runner  v8.0-PROD${RESET}"
    echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}\n"

    # ── PASO 1: Limpiar sesión X previa ───────────────────────────────────────
    echo -e "${BOLD}[1/4] Limpiando sesión X previa...${RESET}"
    if pgrep -x Xorg &>/dev/null; then
        log "Xorg detectado — cerrando..."
        sudo pkill -TERM Xorg 2>/dev/null || true
        sleep 2
        pgrep -x Xorg &>/dev/null && { sudo pkill -KILL Xorg 2>/dev/null || true; sleep 1; }
    fi
    if [[ -f /tmp/.X0-lock ]]; then
        LOCK_PID=$(cat /tmp/.X0-lock 2>/dev/null || echo "0")
        if [[ "$LOCK_PID" -gt 0 ]] && kill -0 "$LOCK_PID" 2>/dev/null; then
            fail "Proceso $LOCK_PID sigue vivo. Mata Xorg manualmente: sudo kill $LOCK_PID"
        fi
        sudo rm -f /tmp/.X0-lock
    fi

    XAUTH_FILE="$REAL_HOME/.Xauthority"
    if [[ -f "$XAUTH_FILE" ]]; then
        XAUTH_OWNER=$(stat -c '%U' "$XAUTH_FILE" 2>/dev/null || echo "unknown")
        [[ "$XAUTH_OWNER" != "$REAL_USER" ]] && sudo rm -f "$XAUTH_FILE"
    fi
    touch "$XAUTH_FILE"
    ok "Entorno X limpio."

    # ── PASO 2: Arrancar Xorg ─────────────────────────────────────────────────
    echo -e "\n${BOLD}[2/4] Iniciando Xorg...${RESET}"
    sudo Xorg "$DISPLAY_NUM" -noreset -nolisten tcp -logfile "$XORG_LOG" "$VT_NUM" &
    XORG_PID=$!
    log "Xorg PID: $XORG_PID — esperando ${XORG_WAIT_SEC}s..."
    sleep "$XORG_WAIT_SEC"
    sudo chmod 644 "$XORG_LOG" 2>/dev/null || true

    export DISPLAY="$DISPLAY_NUM"
    export XAUTHORITY="$XAUTH_FILE"

    ATTEMPT=0
    until xrandr &>/dev/null; do
        ATTEMPT=$((ATTEMPT + 1))
        [[ $ATTEMPT -ge $XORG_RETRY_MAX ]] && fail "Xorg no responde tras $XORG_RETRY_MAX intentos. Ver: $XORG_LOG"
        warn "Xorg aún no responde ($ATTEMPT/$XORG_RETRY_MAX)..."
        sleep 2
    done
    ok "Xorg respondiendo en $DISPLAY_NUM."

    # ── PASO 3: Configurar entorno VAAPI ──────────────────────────────────────
    echo -e "\n${BOLD}[3/4] Configurando entorno VAAPI...${RESET}"
    export LIBVA_DRIVER_NAME="iHD"
    export LIBVA_DRIVERS_PATH="/usr/lib/x86_64-linux-gnu/dri"
    xhost +local: 2>/dev/null && ok "xhost: acceso local concedido." || warn "xhost falló (no crítico)."

    VAINFO_OUT=$(vainfo 2>&1 || true)
    if echo "$VAINFO_OUT" | grep -qi "error\|failed\|cannot"; then
        warn "VAAPI con problemas — Sunshine podría usar CPU."
    else
        H264=$(echo "$VAINFO_OUT" | grep -c "H264\|AVC"  || true)
        HEVC=$(echo "$VAINFO_OUT" | grep -c "HEVC\|H265" || true)
        ok "VAAPI funcional — H.264: ${H264} | HEVC: ${HEVC}"
    fi

    # ── PASO 4: Crear sesión byobu con 1 ventana y 4 panes ───────────────────
    echo -e "\n${BOLD}[4/4] Creando sesión byobu '${BYOBU_SESSION}' con layout 4 panes...${RESET}"

    # String de env para inyectar en cada pane
    ENV_EXPORT="export DISPLAY=${DISPLAY_NUM}; export XAUTHORITY=${XAUTH_FILE}; export LIBVA_DRIVER_NAME=iHD; export LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri"

    # ── Crear sesión con ventana única y pane 0 (xorg log) ───────────────────
    byobu new-session -d -s "$BYOBU_SESSION" -n "$BYOBU_WINDOW" -x 220 -y 50
    # Pane 0: xorg log (top-left)
    byobu send-keys -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.0" \
        "printf '\033]2;xorg-log\033\\\\'; echo '=== XORG LOG EN VIVO ==='; tail -f ${XORG_LOG}" \
        Enter

    # ── Pane 1: i3 (top-center) — split vertical desde pane 0 ───────────────
    byobu split-window -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.0" -h
    byobu send-keys -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.1" \
        "printf '\033]2;i3\033\\\\'; ${ENV_EXPORT}; echo '[i3] Arrancando window manager...'; exec i3 2>&1 | tee ${I3_LOG}" \
        Enter

    # ── Pane 2: sunshine (top-right) — split vertical desde pane 1 ──────────
    byobu split-window -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.1" -h
    byobu send-keys -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.2" \
        "printf '\033]2;sunshine\033\\\\'; ${ENV_EXPORT}; echo '[sunshine] Arrancando servidor...'; ${SUNSHINE_BIN} 2>&1 | tee ${SUNSHINE_LOG}" \
        Enter

    # ── Pane 3: watchdog (bottom, ancho completo) — split horizontal ─────────
    # Seleccionar pane 0 para que el split tome todo el ancho
    byobu select-pane -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.0"
    byobu split-window -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.0" -v -p "$WATCHDOG_PANE_PERCENT"
    # Expandir pane 3 al ancho completo
    byobu select-layout -t "${BYOBU_SESSION}:${BYOBU_WINDOW}" main-horizontal 2>/dev/null || true

    ok "Layout de 4 panes creado."

    # ── Esperar a que i3 y Sunshine arranquen ─────────────────────────────────
    log "Esperando arranque de i3 y Sunshine (3s)..."
    sleep 3

    if pgrep -x i3 &>/dev/null; then
        ok "i3 corriendo (PID $(pgrep -x i3))."
    else
        warn "i3 no detectado aún — ver pane [i3] en byobu."
    fi
    if pgrep -x sunshine &>/dev/null; then
        ok "Sunshine corriendo (PID $(pgrep -x sunshine))."
    else
        warn "Sunshine no detectado aún — puede estar inicializando."
    fi

    # ── Generar script watchdog con variables embebidas ───────────────────────
    local WD_SCRIPT="/tmp/sunshine_watchdog_run.sh"

    cat > "$WD_SCRIPT" << WDEOF
#!/usr/bin/env bash
# Watchdog autogenerado por run_sunshine.sh v8.0-PROD — NO editar manualmente

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "\${CYAN}[INFO]\${RESET}  \$(date '+%H:%M:%S') \$*" | tee -a "${WATCHDOG_LOG}"; }
ok()   { echo -e "\${GREEN}[OK]\${RESET}    \$(date '+%H:%M:%S') \$*" | tee -a "${WATCHDOG_LOG}"; }
warn() { echo -e "\${YELLOW}[WARN]\${RESET}  \$(date '+%H:%M:%S') \$*" | tee -a "${WATCHDOG_LOG}"; }

# Variables embebidas en el momento del start
export DISPLAY="${DISPLAY_NUM}"
export XAUTHORITY="${REAL_HOME}/.Xauthority"
export LIBVA_DRIVER_NAME="iHD"
export LIBVA_DRIVERS_PATH="/usr/lib/x86_64-linux-gnu/dri"
REAL_USER="${REAL_USER}"
REAL_HOME="${REAL_HOME}"
DISPLAY_NUM="${DISPLAY_NUM}"
VT_NUM="${VT_NUM}"
XORG_LOG="${XORG_LOG}"
I3_LOG="${I3_LOG}"
SUNSHINE_LOG="${SUNSHINE_LOG}"
XORG_WAIT_SEC="${XORG_WAIT_SEC}"
XORG_RETRY_MAX="${XORG_RETRY_MAX}"
SUNSHINE_BIN="${SUNSHINE_BIN}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL}"
WATCHDOG_BACKOFF_MAX="${WATCHDOG_BACKOFF_MAX}"
PID_FILE="${PID_FILE}"
BYOBU_SESSION="${BYOBU_SESSION}"
BYOBU_WINDOW="${BYOBU_WINDOW}"

# ── Trap de limpieza ──────────────────────────────────────────────────────────
cleanup() {
    warn "[WD] Señal recibida — deteniendo todo..."
    pkill -TERM sunshine  2>/dev/null || true; sleep 2
    pkill -TERM i3        2>/dev/null || true
    sudo pkill -TERM Xorg 2>/dev/null || true; sleep 1
    sudo rm -f /tmp/.X0-lock
    rm -f "\$PID_FILE"
    warn "[WD] Detenido limpiamente."
    exit 0
}
trap cleanup SIGINT SIGTERM

# ── restart_xorg ──────────────────────────────────────────────────────────────
restart_xorg() {
    warn "[WD] Reiniciando Xorg..."
    sudo pkill -TERM Xorg 2>/dev/null || true; sleep 2
    sudo pkill -KILL Xorg 2>/dev/null || true; sleep 1
    sudo rm -f /tmp/.X0-lock

    local XAUTH_FILE="\$REAL_HOME/.Xauthority"
    local XAUTH_OWNER
    XAUTH_OWNER=\$(stat -c '%U' "\$XAUTH_FILE" 2>/dev/null || echo "unknown")
    [[ "\$XAUTH_OWNER" != "\$REAL_USER" ]] && sudo rm -f "\$XAUTH_FILE"
    touch "\$XAUTH_FILE"

    sudo Xorg "\$DISPLAY_NUM" -noreset -nolisten tcp -logfile "\$XORG_LOG" "\$VT_NUM" &
    sleep "\$XORG_WAIT_SEC"
    sudo chmod 644 "\$XORG_LOG" 2>/dev/null || true
    export DISPLAY="\$DISPLAY_NUM"
    export XAUTHORITY="\$XAUTH_FILE"

    local ATTEMPT=0
    until xrandr &>/dev/null; do
        ATTEMPT=\$((ATTEMPT + 1))
        [[ \$ATTEMPT -ge \$XORG_RETRY_MAX ]] && {
            warn "[WD] Xorg no responde tras \$XORG_RETRY_MAX intentos."
            return 1
        }
        warn "[WD] Esperando Xorg (\$ATTEMPT/\$XORG_RETRY_MAX)..."
        sleep 2
    done
    xhost +local: 2>/dev/null || true
    # Refrescar pane xorg con nuevo log
    byobu send-keys -t "\${BYOBU_SESSION}:\${BYOBU_WINDOW}.0" \
        "echo '=== XORG REINICIADO ==='; tail -f \${XORG_LOG}" Enter 2>/dev/null || true
    ok "[WD] Xorg recuperado."
}

# ── restart_i3 ────────────────────────────────────────────────────────────────
restart_i3() {
    warn "[WD] Reiniciando i3..."
    pkill -TERM i3 2>/dev/null || true; sleep 1
    byobu send-keys -t "\${BYOBU_SESSION}:\${BYOBU_WINDOW}.1" \
        "export DISPLAY=\${DISPLAY_NUM}; export XAUTHORITY=\${REAL_HOME}/.Xauthority; export LIBVA_DRIVER_NAME=iHD; echo '[i3] Reiniciando...'; exec i3 2>&1 | tee -a \${I3_LOG}" \
        Enter 2>/dev/null || true
    sleep 3
    if pgrep -x i3 &>/dev/null; then
        ok "[WD] i3 recuperado (PID \$(pgrep -x i3))."
        return 0
    else
        warn "[WD] i3 no arrancó."
        return 1
    fi
}

# ── restart_sunshine ──────────────────────────────────────────────────────────
restart_sunshine() {
    warn "[WD] Reiniciando Sunshine..."
    pkill -TERM sunshine 2>/dev/null || true; sleep 2
    pkill -KILL sunshine 2>/dev/null || true; sleep 1
    byobu send-keys -t "\${BYOBU_SESSION}:\${BYOBU_WINDOW}.2" \
        "export DISPLAY=\${DISPLAY_NUM}; export XAUTHORITY=\${REAL_HOME}/.Xauthority; export LIBVA_DRIVER_NAME=iHD; export LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri; echo '[sunshine] Reiniciando...'; \${SUNSHINE_BIN} 2>&1 | tee -a \${SUNSHINE_LOG}" \
        Enter 2>/dev/null || true
    sleep 3
    if pgrep -x sunshine &>/dev/null; then
        ok "[WD] Sunshine recuperado (PID \$(pgrep -x sunshine))."
        return 0
    else
        warn "[WD] Sunshine no arrancó."
        return 1
    fi
}

# ── Registrar PID propio ──────────────────────────────────────────────────────
echo \$\$ > "\$PID_FILE"

# ── Cabecera ──────────────────────────────────────────────────────────────────
clear
echo -e "\${BOLD}══════════════════════════════════════════════════════\${RESET}"
echo -e "\${BOLD}  WATCHDOG — Sunshine Health Monitor  v8.0-PROD\${RESET}"
echo -e "\${BOLD}══════════════════════════════════════════════════════\${RESET}"
log "[WD] PID \$\$ | Intervalo base: \${WATCHDOG_INTERVAL}s | Backoff máx: \${WATCHDOG_BACKOFF_MAX}s"
log "[WD] Monitorizando: Xorg ● i3 ● Sunshine"
log "[WD] Log: ${WATCHDOG_LOG}"
echo ""

XORG_FAILS=0
I3_FAILS=0
SUN_FAILS=0
SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
CYCLE=0

while true; do
    sleep "\$SLEEP_INTERVAL"
    CYCLE=\$((CYCLE + 1))

    XORG_PID="\$(pgrep -x Xorg     2>/dev/null | head -1 || echo '')"
    I3_PID="\$(  pgrep -x i3       2>/dev/null | head -1 || echo '')"
    SUN_PID="\$( pgrep -x sunshine 2>/dev/null | head -1 || echo '')"

    XORG_ST="\$([[ -n \"\$XORG_PID\" ]] && echo \"OK[\${XORG_PID}]\" || echo 'CAÍDO')"
    I3_ST="\$(  [[ -n \"\$I3_PID\"   ]] && echo \"OK[\${I3_PID}]\"   || echo 'CAÍDO')"
    SUN_ST="\$( [[ -n \"\$SUN_PID\"  ]] && echo \"OK[\${SUN_PID}]\"  || echo 'CAÍDO')"

    log "[WD] Ciclo #\${CYCLE} | Xorg:\${XORG_ST} | i3:\${I3_ST} | Sunshine:\${SUN_ST} | próx:\${SLEEP_INTERVAL}s"

    # ── Xorg caído → reiniciar stack completo ────────────────────────────────
    if [[ -z "\$XORG_PID" ]]; then
        XORG_FAILS=\$((XORG_FAILS + 1))
        warn "[WD] ⚠ Xorg CAÍDO (fallo #\${XORG_FAILS}) — reiniciando stack completo..."
        if restart_xorg; then
            XORG_FAILS=0
            restart_i3       || I3_FAILS=\$((I3_FAILS + 1))
            restart_sunshine || SUN_FAILS=\$((SUN_FAILS + 1))
            SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
        else
            SLEEP_INTERVAL=\$(( SLEEP_INTERVAL + WATCHDOG_INTERVAL ))
            [[ \$SLEEP_INTERVAL -gt \$WATCHDOG_BACKOFF_MAX ]] && SLEEP_INTERVAL=\$WATCHDOG_BACKOFF_MAX
            warn "[WD] Backoff activo — próximo intento en \${SLEEP_INTERVAL}s"
        fi
        continue
    else
        XORG_FAILS=0
    fi

    # ── i3 caído → reiniciar solo i3 ─────────────────────────────────────────
    if [[ -z "\$I3_PID" ]]; then
        I3_FAILS=\$((I3_FAILS + 1))
        warn "[WD] ⚠ i3 CAÍDO (fallo #\${I3_FAILS}) — reiniciando solo i3..."
        if restart_i3; then
            I3_FAILS=0
            SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
        else
            SLEEP_INTERVAL=\$(( SLEEP_INTERVAL + WATCHDOG_INTERVAL ))
            [[ \$SLEEP_INTERVAL -gt \$WATCHDOG_BACKOFF_MAX ]] && SLEEP_INTERVAL=\$WATCHDOG_BACKOFF_MAX
            warn "[WD] Backoff activo — próximo intento en \${SLEEP_INTERVAL}s"
        fi
    else
        I3_FAILS=0
    fi

    # ── Sunshine caído → reiniciar solo Sunshine ──────────────────────────────
    if [[ -z "\$SUN_PID" ]]; then
        SUN_FAILS=\$((SUN_FAILS + 1))
        warn "[WD] ⚠ Sunshine CAÍDO (fallo #\${SUN_FAILS}) — reiniciando solo Sunshine..."
        if restart_sunshine; then
            SUN_FAILS=0
            SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
        else
            SLEEP_INTERVAL=\$(( SLEEP_INTERVAL + WATCHDOG_INTERVAL ))
            [[ \$SLEEP_INTERVAL -gt \$WATCHDOG_BACKOFF_MAX ]] && SLEEP_INTERVAL=\$WATCHDOG_BACKOFF_MAX
            warn "[WD] Backoff activo — próximo intento en \${SLEEP_INTERVAL}s"
        fi
    else
        SUN_FAILS=0
        SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
    fi

done
WDEOF

    chmod +x "$WD_SCRIPT"

    # ── Lanzar watchdog en pane 3 (bottom, ancho completo) ───────────────────
    byobu send-keys -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.3" \
        "exec ${WD_SCRIPT}" \
        Enter

    sleep 2

    # Guardar PID del pane watchdog (el script sobreescribirá con su propio PID)
    WD_PID=$(byobu list-panes -t "${BYOBU_SESSION}:${BYOBU_WINDOW}" -F "#{pane_pid}" 2>/dev/null | tail -1 || echo "?")
    echo "$WD_PID" > "$PID_FILE"

    # Dejar el foco en el pane del watchdog al hacer attach
    byobu select-pane -t "${BYOBU_SESSION}:${BYOBU_WINDOW}.3"

    ok "Sesión '${BYOBU_SESSION}' lista — 1 ventana, 4 panes."

    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  ✔ Sistema en ejecución — v8.0-PROD${RESET}"
    echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "  ${BOLD}Layout de panes:${RESET}"
    echo -e "  ┌─────────────┬─────────────┬─────────────┐"
    echo -e "  │  xorg log   │     i3      │   sunshine  │"
    echo -e "  ├─────────────┴─────────────┴─────────────┤"
    echo -e "  │          watchdog (monitor)              │"
    echo -e "  └─────────────────────────────────────────┘"
    echo ""
    echo -e "  ${BOLD}Web UI         :${RESET}  https://localhost:47990"
    echo ""
    echo -e "  ${BOLD}▶ Conectar     :${RESET}  ${CYAN}byobu attach-session -t ${BYOBU_SESSION}${RESET}"
    echo ""
    echo -e "  ${BOLD}Navegar panes  :${RESET}  Ctrl+B + flechas  (o Ctrl+B + Q + número)"
    echo -e "  ${BOLD}Zoom un pane   :${RESET}  Ctrl+B + Z"
    echo -e "  ${BOLD}Desconectar    :${RESET}  Ctrl+B + D  (la sesión sigue corriendo)"
    echo -e "  ${BOLD}Estado         :${RESET}  $0 status"
    echo -e "  ${BOLD}Apagar todo    :${RESET}  $0 stop"
    echo ""
}

# =============================================================================
# CMD_STOP
# =============================================================================
cmd_stop() {
    echo -e "\n${BOLD}[STOP] Deteniendo todo...${RESET}"

    # Detener watchdog por PID
    if [[ -f "$PID_FILE" ]]; then
        WD_PID=$(cat "$PID_FILE")
        if kill -0 "$WD_PID" 2>/dev/null; then
            kill -TERM "$WD_PID" 2>/dev/null && ok "Watchdog (PID $WD_PID) detenido."
            sleep 1
        else
            warn "PID $WD_PID ya no existe."
        fi
        rm -f "$PID_FILE"
    else
        warn "PID file no encontrado."
    fi

    # Destruir sesión byobu completamente
    _kill_byobu_session

    # Matar procesos
    pkill -TERM sunshine 2>/dev/null && ok "Sunshine detenido." || true
    pkill -TERM i3       2>/dev/null && ok "i3 detenido."       || true
    sleep 2
    sudo pkill -TERM Xorg 2>/dev/null && ok "Xorg detenido."    || true
    sleep 1
    sudo pkill -KILL Xorg 2>/dev/null || true
    sudo rm -f /tmp/.X0-lock
    ok "Limpieza completada."
}

# =============================================================================
# CMD_RESTART
# =============================================================================
cmd_restart() {
    echo -e "\n${BOLD}[RESTART] Reiniciando...${RESET}"
    cmd_stop
    sleep 2
    cmd_start
}

# =============================================================================
# CMD_STATUS
# =============================================================================
cmd_status() {
    echo -e "\n${BOLD}══════════ STATUS ══════════${RESET}"
    pgrep -x Xorg     &>/dev/null \
        && ok  "Xorg      : CORRIENDO (PID $(pgrep -x Xorg))" \
        || warn "Xorg      : DETENIDO"
    pgrep -x i3       &>/dev/null \
        && ok  "i3        : CORRIENDO (PID $(pgrep -x i3))" \
        || warn "i3        : DETENIDO"
    pgrep -x sunshine &>/dev/null \
        && ok  "Sunshine  : CORRIENDO (PID $(pgrep -x sunshine))" \
        || warn "Sunshine  : DETENIDO"
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        ok  "Watchdog  : ACTIVO (PID $(cat "$PID_FILE"), cada ${WATCHDOG_INTERVAL}s)"
    else
        warn "Watchdog  : INACTIVO"
    fi
    if byobu has-session -t "$BYOBU_SESSION" 2>/dev/null; then
        ok  "Byobu     : sesión '${BYOBU_SESSION}' activa"
        echo ""
        echo -e "  ${BOLD}Panes activos:${RESET}"
        byobu list-panes -t "${BYOBU_SESSION}:${BYOBU_WINDOW}" \
            -F "  pane ##{pane_index}: #{pane_title} (PID #{pane_pid})" 2>/dev/null || true
    else
        warn "Byobu     : sesión '${BYOBU_SESSION}' no encontrada"
    fi
    echo ""
}

# =============================================================================
# CMD_LOGS
# =============================================================================
cmd_logs() {
    local LOG="${1:-watchdog}"
    case "$LOG" in
        watchdog) tail -f "$WATCHDOG_LOG"  ;;
        sunshine) tail -f "$SUNSHINE_LOG"  ;;
        xorg)     tail -f "$XORG_LOG"      ;;
        i3)       tail -f "$I3_LOG"        ;;
        *)
            echo "Logs disponibles: watchdog | sunshine | xorg | i3"
            echo "Ejemplo: $0 logs sunshine"
            ;;
    esac
}

# =============================================================================
# DISPATCHER
# =============================================================================
case "${1:-}" in
    start)   cmd_start          ;;
    stop)    cmd_stop           ;;
    restart) cmd_restart        ;;
    status)  cmd_status         ;;
    logs)    cmd_logs "${2:-}"  ;;
    *)
        echo -e "\n${BOLD}Uso:${RESET}"
        echo -e "  ${CYAN}$0 start${RESET}              — Encender todo"
        echo -e "  ${CYAN}$0 stop${RESET}               — Apagar todo limpiamente"
        echo -e "  ${CYAN}$0 restart${RESET}            — Stop + start en un paso"
        echo -e "  ${CYAN}$0 status${RESET}             — Estado de los procesos y panes"
        echo -e "  ${CYAN}$0 logs${RESET}               — Log watchdog en vivo"
        echo -e "  ${CYAN}$0 logs sunshine${RESET}      — Log de Sunshine"
        echo -e "  ${CYAN}$0 logs xorg${RESET}          — Log de Xorg"
        echo -e "  ${CYAN}$0 logs i3${RESET}            — Log de i3"
        echo ""
        echo -e "  ${CYAN}byobu attach-session -t sunshine${RESET}"
        echo -e "  Navegar panes : Ctrl+B + flechas"
        echo -e "  Zoom un pane  : Ctrl+B + Z"
        echo -e "  Desconectar   : Ctrl+B + D"
        echo ""
        exit 1
        ;;
esac

