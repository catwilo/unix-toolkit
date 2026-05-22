#!/usr/bin/env bash
# =============================================================================
# lib/watchdog.sh — Generador y launcher del watchdog de Sunshine
#
# El watchdog se genera como script en disco (no inline bash -c) y se
# ejecuta en un pane byobu dedicado.
#
# Orden de dependencias (invariante):
#   Xorg → i3 → Sunshine
# Si cae Xorg: reinicia Xorg → i3 → Sunshine
# Si cae i3:   reinicia i3   → Sunshine
# Si cae Sunshine: reinicia solo Sunshine
#
# Variables requeridas: todas las de config (embebidas en el script generado).
# =============================================================================

# ── generate_watchdog ─────────────────────────────────────────────────────────
# Escribe el script watchdog en WD_SCRIPT con todas las variables embebidas.
generate_watchdog() {
    cat > "$WD_SCRIPT" << WDEOF
#!/usr/bin/env bash
# Watchdog autogenerado — NO editar manualmente.
# Generado por: run_sunshine.sh  $(date '+%Y-%m-%d %H:%M:%S')

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

_ts() { date '+%H:%M:%S'; }
log()  { echo -e "\${CYAN}●\${RESET}  \${DIM}\$(_ts)\${RESET}  \$*" | tee -a "${WATCHDOG_LOG}"; }
ok()   { echo -e "\${GREEN}✔\${RESET}  \${DIM}\$(_ts)\${RESET}  \$*" | tee -a "${WATCHDOG_LOG}"; }
warn() { echo -e "\${YELLOW}⚠\${RESET}  \${DIM}\$(_ts)\${RESET}  \$*" | tee -a "${WATCHDOG_LOG}"; }

# ── Variables embebidas ───────────────────────────────────────────────────────
export DISPLAY="${DISPLAY_NUM}"
export XAUTHORITY="${REAL_HOME}/.Xauthority"
export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}"
export LIBVA_DRIVERS_PATH="${LIBVA_DRIVERS_PATH:-/usr/lib/x86_64-linux-gnu/dri}"

REAL_USER="${REAL_USER}"
REAL_HOME="${REAL_HOME}"
DISPLAY_NUM="${DISPLAY_NUM}"
VT_NUM="${VT_NUM}"
XORG_LOG="${XORG_LOG}"
SUNSHINE_LOG="${SUNSHINE_LOG}"
XORG_WAIT_SEC="${XORG_WAIT_SEC}"
XORG_RETRY_MAX="${XORG_RETRY_MAX}"
SUNSHINE_BIN="${SUNSHINE_BIN}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL}"
WATCHDOG_BACKOFF_MAX="${WATCHDOG_BACKOFF_MAX}"
PID_FILE="${PID_FILE}"
PANE_I3="${PANE_I3}"
PANE_SUNSHINE="${PANE_SUNSHINE}"

# ── Registrar PID propio ──────────────────────────────────────────────────────
echo \$\$ > "\$PID_FILE"

# ── Trap de salida limpia ─────────────────────────────────────────────────────
_wd_cleanup() {
    warn "[WD] Señal recibida — watchdog deteniéndose (procesos X/i3/Sunshine intactos)."
    rm -f "\$PID_FILE"
    exit 0
}
trap _wd_cleanup SIGINT SIGTERM

# ── Helpers de restart (orden de dependencias) ────────────────────────────────

_x11_running() {
    local lock="/tmp/.X\${DISPLAY_NUM#:}-lock"
    if [[ -f "\$lock" ]]; then
        local pid; pid=\$(cat "\$lock" 2>/dev/null | tr -d ' ' || echo "0")
        [[ "\$pid" -gt 0 ]] && kill -0 "\$pid" 2>/dev/null
    else
        return 1
    fi
}

_x11_responsive() {
    DISPLAY="\$DISPLAY_NUM" XAUTHORITY="\$REAL_HOME/.Xauthority" xrandr &>/dev/null
}

wd_restart_xorg() {
    warn "[WD] Reiniciando Xorg..."
    sudo pkill -TERM Xorg 2>/dev/null || true; sleep 2
    sudo pkill -KILL Xorg 2>/dev/null || true; sleep 1
    sudo rm -f "/tmp/.X\${DISPLAY_NUM#:}-lock"

    local xauth="\$REAL_HOME/.Xauthority"
    local owner; owner=\$(stat -c '%U' "\$xauth" 2>/dev/null || echo "unknown")
    [[ "\$owner" != "\$REAL_USER" ]] && sudo rm -f "\$xauth"
    touch "\$xauth"

    sudo Xorg "\$DISPLAY_NUM" -noreset -nolisten tcp -logfile "\$XORG_LOG" "\$VT_NUM" &>/dev/null &
    sleep "\$XORG_WAIT_SEC"
    sudo chmod 644 "\$XORG_LOG" 2>/dev/null || true
    export DISPLAY="\$DISPLAY_NUM"; export XAUTHORITY="\$xauth"

    local attempt=0
    until _x11_responsive; do
        attempt=\$((attempt + 1))
        if [[ \$attempt -ge \$XORG_RETRY_MAX ]]; then
            warn "[WD] Xorg no responde tras \${XORG_RETRY_MAX} intentos."
            return 1
        fi
        warn "[WD] Esperando Xorg (\${attempt}/\${XORG_RETRY_MAX})..."
        sleep 2
    done
    xhost +local: &>/dev/null || true
    local _xpid; _xpid=\$(pgrep -x Xorg 2>/dev/null | head -1 || true)
    ok "[WD] Xorg recuperado (PID \${_xpid})."
}

wd_restart_i3() {
    warn "[WD] Reiniciando i3..."
    pkill -TERM i3 2>/dev/null || true; sleep 1
    byobu send-keys -t "\$PANE_I3" \
        "export DISPLAY=\${DISPLAY_NUM}; export XAUTHORITY=\${REAL_HOME}/.Xauthority; \
export LIBVA_DRIVER_NAME=\${LIBVA_DRIVER_NAME}; echo '[i3] Reiniciando...'; exec i3 2>&1" \
        Enter 2>/dev/null || true
    sleep 3
    local _i3pid; _i3pid=\$(pgrep -x i3 2>/dev/null | head -1 || true)
    if [[ -n "\$_i3pid" ]]; then
        ok "[WD] i3 recuperado (PID \${_i3pid})."
        return 0
    else
        warn "[WD] i3 no arrancó."
        return 1
    fi
}

wd_restart_sunshine() {
    warn "[WD] Reiniciando Sunshine..."
    pkill -TERM sunshine 2>/dev/null || true; sleep 2
    pkill -KILL sunshine 2>/dev/null || true; sleep 1

    local env_str="export DISPLAY=\${DISPLAY_NUM}; export XAUTHORITY=\${REAL_HOME}/.Xauthority; \
export LIBVA_DRIVER_NAME=\${LIBVA_DRIVER_NAME}; export LIBVA_DRIVERS_PATH=\${LIBVA_DRIVERS_PATH}"

    byobu send-keys -t "\$PANE_SUNSHINE" \
        "\${env_str}; echo '[sunshine] Reiniciando...'; \${SUNSHINE_BIN} 2>&1 | tee -a \${SUNSHINE_LOG}" \
        Enter 2>/dev/null || true
    sleep 3
    local _sunpid; _sunpid=\$(pgrep -x sunshine 2>/dev/null | head -1 || true)
    if [[ -n "\$_sunpid" ]]; then
        ok "[WD] Sunshine recuperado (PID \${_sunpid})."
        return 0
    else
        warn "[WD] Sunshine no arrancó."
        return 1
    fi
}

# ── Backoff helper ────────────────────────────────────────────────────────────
_backoff() {
    local cur="\$1"
    local next=\$(( cur + WATCHDOG_INTERVAL ))
    if [[ \$next -gt \$WATCHDOG_BACKOFF_MAX ]]; then next=\$WATCHDOG_BACKOFF_MAX; fi
    echo "\$next"
}

# ── Cabecera ──────────────────────────────────────────────────────────────────
: > /dev/null  # noop
mkdir -p "\$(dirname "${WATCHDOG_LOG}")" 2>/dev/null || true
touch "${WATCHDOG_LOG}" 2>/dev/null || true
clear
_wd_line() { local w=\${COLUMNS:-50}; (( w>50 )) && w=50; (( w<24 )) && w=24; printf '%*s' "\$w" '' | tr ' ' '─'; }
echo -e "\${BOLD}\${CYAN}\$(_wd_line)\${RESET}"
echo -e "\${BOLD}  WATCHDOG — Sunshine Health Monitor\${RESET}"
echo -e "\${BOLD}\${CYAN}\$(_wd_line)\${RESET}"
log "[WD] PID \$\$ | Intervalo: \${WATCHDOG_INTERVAL}s | Backoff máx: \${WATCHDOG_BACKOFF_MAX}s"
log "[WD] Monitorizando: Xorg → i3 → Sunshine"
echo ""

XORG_FAILS=0; I3_FAILS=0; SUN_FAILS=0
SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
CYCLE=0

# ── Loop principal ────────────────────────────────────────────────────────────
while true; do
    sleep "\$SLEEP_INTERVAL"
    CYCLE=\$((CYCLE + 1))

    XORG_PID="\$(pgrep -x Xorg     2>/dev/null | head -1 || echo '')"
    I3_PID="\$(  pgrep -x i3       2>/dev/null | head -1 || echo '')"
    SUN_PID="\$( pgrep -x sunshine 2>/dev/null | head -1 || echo '')"

    XORG_ST="\$([[ -n \"\$XORG_PID\" ]] && echo \"\${GREEN}OK[\${XORG_PID}]\${RESET}\" || echo \"\${RED}CAÍDO\${RESET}\")"
    I3_ST="\$(  [[ -n \"\$I3_PID\"   ]] && echo \"\${GREEN}OK[\${I3_PID}]\${RESET}\"   || echo \"\${RED}CAÍDO\${RESET}\")"
    SUN_ST="\$( [[ -n \"\$SUN_PID\"  ]] && echo \"\${GREEN}OK[\${SUN_PID}]\${RESET}\"  || echo \"\${RED}CAÍDO\${RESET}\")"

    echo -e "\${DIM}[\${CYCLE}] \$(date '+%H:%M:%S')\${RESET}  Xorg:\${XORG_ST}  i3:\${I3_ST}  Sunshine:\${SUN_ST}  next:\${SLEEP_INTERVAL}s" \
        | tee -a "${WATCHDOG_LOG}"

    # ── 1. Xorg caído → reiniciar Xorg → i3 → Sunshine ──────────────────────
    if [[ -z "\$XORG_PID" ]]; then
        XORG_FAILS=\$((XORG_FAILS + 1))
        warn "[WD] Xorg CAÍDO (fallo #\${XORG_FAILS})"
        if wd_restart_xorg; then
            XORG_FAILS=0
            wd_restart_i3       || I3_FAILS=\$((I3_FAILS + 1))
            wd_restart_sunshine || SUN_FAILS=\$((SUN_FAILS + 1))
            SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
        else
            SLEEP_INTERVAL=\$(_backoff "\$SLEEP_INTERVAL")
            warn "[WD] Backoff → próximo intento en \${SLEEP_INTERVAL}s"
        fi
        continue
    else
        XORG_FAILS=0
    fi

    # ── 2. i3 caído → reiniciar i3 → Sunshine ────────────────────────────────
    if [[ -z "\$I3_PID" ]]; then
        I3_FAILS=\$((I3_FAILS + 1))
        warn "[WD] i3 CAÍDO (fallo #\${I3_FAILS})"
        if wd_restart_i3; then
            I3_FAILS=0
            wd_restart_sunshine || SUN_FAILS=\$((SUN_FAILS + 1))
            SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
        else
            SLEEP_INTERVAL=\$(_backoff "\$SLEEP_INTERVAL")
            warn "[WD] Backoff → próximo intento en \${SLEEP_INTERVAL}s"
        fi
        continue
    else
        I3_FAILS=0
    fi

    # ── 3. Solo Sunshine caído → reiniciar solo Sunshine ─────────────────────
    if [[ -z "\$SUN_PID" ]]; then
        SUN_FAILS=\$((SUN_FAILS + 1))
        warn "[WD] Sunshine CAÍDO (fallo #\${SUN_FAILS})"
        if wd_restart_sunshine; then
            SUN_FAILS=0
            SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
        else
            SLEEP_INTERVAL=\$(_backoff "\$SLEEP_INTERVAL")
            warn "[WD] Backoff → próximo intento en \${SLEEP_INTERVAL}s"
        fi
    else
        SUN_FAILS=0
        SLEEP_INTERVAL=\$WATCHDOG_INTERVAL
    fi
done
WDEOF

    chmod +x "$WD_SCRIPT"
    log "Watchdog script generado: ${WD_SCRIPT}"
}

# ── launch_watchdog ───────────────────────────────────────────────────────────
# Lanza el watchdog en el pane byobu dedicado.
launch_watchdog() {
    byobu send-keys -t "$PANE_WATCHDOG" \
        "exec ${WD_SCRIPT}" \
        Enter 2>/dev/null || {
        warn "No se pudo lanzar watchdog en byobu — lanzando en background..."
        bash "$WD_SCRIPT" &
    }
    sleep 1
    # El script sobreescribirá PID_FILE con su propio PID.
    log "Watchdog activo."
}

# ── watchdog_running ──────────────────────────────────────────────────────────
watchdog_running() {
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
}

# ── stop_watchdog ─────────────────────────────────────────────────────────────
stop_watchdog() {
    if watchdog_running; then
        local pid; pid=$(cat "$PID_FILE" 2>/dev/null || true)
        kill -TERM "$pid" 2>/dev/null && ok "Watchdog (PID ${pid}) detenido." || true
        sleep 1
        rm -f "$PID_FILE"
    else
        log "Watchdog no está corriendo."
    fi
}
