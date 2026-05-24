#!/usr/bin/env bash
# =============================================================================
# run_sunshine.sh — Servidor Sunshine headless (X11 + i3 + watchdog + byobu)
# Versión: 9.0-PROD
#
# Uso:
#   ./run_sunshine.sh start              → Enciende todo
#   ./run_sunshine.sh stop               → Mata Sunshine/watchdog; deja X11
#   ./run_sunshine.sh stop --force-xorg  → Además mata X11
#   ./run_sunshine.sh restart            → Solo reinicia Sunshine
#   ./run_sunshine.sh status             → Estado de todos los procesos
#   ./run_sunshine.sh logs [sunshine|xorg|watchdog]
#   ./run_sunshine.sh attach             → byobu attach a la sesión
#
# Ejecutar como usuario NORMAL (nunca root).
# =============================================================================
set -uo pipefail
IFS=$'\n\t'

# ── Resolución de rutas ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/x11.sh"
source "${LIB_DIR}/sunshine.sh"
source "${LIB_DIR}/watchdog.sh"

# =============================================================================
# CONFIGURACIÓN — editar aquí o sobreescribir con variables de entorno
# =============================================================================
DISPLAY_NUM="${DISPLAY_NUM:-:0}"
VT_NUM="${VT_NUM:-vt1}"

XORG_LOG="${XORG_LOG:-/tmp/xorg_sunshine.log}"
SUNSHINE_LOG="${SUNSHINE_LOG:-/tmp/sunshine_run.log}"
WATCHDOG_LOG="${WATCHDOG_LOG:-/tmp/sunshine_watchdog.log}"
LOG_FILE="${LOG_FILE:-/tmp/run_sunshine_main.log}"

XORG_WAIT_SEC="${XORG_WAIT_SEC:-5}"
XORG_RETRY_MAX="${XORG_RETRY_MAX:-10}"
SUNSHINE_BIN="${SUNSHINE_BIN:-sunshine}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-7}"
WATCHDOG_BACKOFF_MAX="${WATCHDOG_BACKOFF_MAX:-21}"
PID_FILE="${PID_FILE:-/tmp/sunshine_watchdog.pid}"
WD_SCRIPT="${WD_SCRIPT:-/tmp/sunshine_watchdog_run.sh}"

# ── Binario REAL de Sunshine ───────────────────────────────────────────────────
# El wrapper en ~/.local/bin/sunshine tiene el mismo nombre que el binario real
# y, al ir primero en el PATH, 'sunshine' a secas resolvería al wrapper → bucle.
# Por eso buscamos el binario del paquete en rutas del sistema, ignorando
# cualquier ejecutable bajo ~/.local/bin. Si el usuario fija SUNSHINE_BIN, manda.
_resolve_sunshine_bin() {
    local c
    for c in /usr/bin/sunshine /usr/local/bin/sunshine /bin/sunshine; do
        [[ -x "$c" ]] && { printf '%s' "$c"; return 0; }
    done
    # Fallback: primer 'sunshine' del PATH que NO esté en ~/.local/bin.
    local p
    while IFS= read -r p; do
        [[ "$p" == "${HOME}/.local/bin/"* ]] && continue
        [[ -x "$p" ]] && { printf '%s' "$p"; return 0; }
    done < <(command -v -a sunshine 2>/dev/null)
    return 1
}
SUNSHINE_BIN="${SUNSHINE_BIN:-$(_resolve_sunshine_bin || echo sunshine)}"
# Si SUNSHINE_BIN apunta al wrapper, forzar resolución real
if [[ "${SUNSHINE_BIN}" == "${HOME}/.local/bin/"* ]] || [[ "${SUNSHINE_BIN}" == "sunshine" ]]; then
    SUNSHINE_BIN="$(_resolve_sunshine_bin || echo /usr/bin/sunshine)"
fi

LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-iHD}"
LIBVA_DRIVERS_PATH="${LIBVA_DRIVERS_PATH:-/usr/lib/x86_64-linux-gnu/dri}"

# ── Modelo de sesión ──────────────────────────────────────────────────────────
# La SESIÓN byobu es del usuario; el script NUNCA la crea ni la mata.
# Si ya estás dentro de una sesión, se usa esa. Si no hay ninguna, se
# usa/crea una sesión persistente llamada 'default'.
# El script solo administra UNA VENTANA llamada 'sunshine' (con sus 4 panes).
# 'stop' cierra SOLO esa ventana, jamás la sesión ni tus otras ventanas.
BYOBU_SESSION=""                         # se resuelve en runtime
BYOBU_DEFAULT_SESSION="${BYOBU_DEFAULT_SESSION:-default}"
BYOBU_WINDOW="${BYOBU_WINDOW:-sunshine}"

REAL_USER="$USER"
REAL_HOME="$HOME"

# =============================================================================
# GUARDIA ROOT
# =============================================================================
[[ $EUID -eq 0 ]] && fail "NO ejecutes como root. Usa tu usuario normal."

# =============================================================================
# CMD_START
# =============================================================================
cmd_start() {
    banner "Sunshine Runner  v9.0-PROD" "display=${DISPLAY_NUM}  user=${REAL_USER}"

    # ── Preflight ──────────────────────────────────────────────────────────────
    step 1 4 "Verificando dependencias"
    local miss=0 bin grp
    for bin in xrandr vainfo sudo byobu tmux i3 "$SUNSHINE_BIN"; do
        command -v "$bin" &>/dev/null \
            && ok "${bin}" \
            || { warn "No encontrado: '${bin}'"; miss=$((miss+1)); }
    done
    for grp in video render input; do
        id -nG "$REAL_USER" | grep -qw "$grp" \
            || warn "Usuario no está en grupo '${grp}'."
    done
    [[ "$miss" -gt 0 ]] && fail "Faltan binarios requeridos. Ejecuta setup.sh primero."

    # ── Watchdog guard ─────────────────────────────────────────────────────────
    if watchdog_running; then
        local _wd_pid; _wd_pid=$(cat "$PID_FILE" 2>/dev/null || true)
        warn "Sistema ya en ejecución (watchdog PID ${_wd_pid})."
        warn "Usa 'restart' para reiniciar solo Sunshine, o 'stop' para detener todo."
        exit 1
    fi

    # ── X11 ────────────────────────────────────────────────────────────────────
    step 2 4 "Asegurando X11 en ${DISPLAY_NUM}"
    ensure_x11 || fail "No se pudo iniciar X11. Ver: ${XORG_LOG}"

    # ── VAAPI ──────────────────────────────────────────────────────────────────
    step 3 4 "Configurando VAAPI"
    vaapi_setup

    # ── Byobu + procesos ───────────────────────────────────────────────────────
    step 4 4 "Creando ventana byobu '${BYOBU_WINDOW}'"
    _setup_byobu_window
    _launch_all_in_byobu

    _print_summary
}

# ── _resolve_session ──────────────────────────────────────────────────────────
# Determina en qué sesión trabajar, sin apropiarse de ella:
#   1. Si se ejecuta DENTRO de tmux/byobu → usa esa misma sesión.
#   2. Si no, usa la sesión persistente 'default' (la crea solo si no existe).
# Resultado en la global BYOBU_SESSION.
_resolve_session() {
    if [[ -n "${TMUX:-}" ]]; then
        BYOBU_SESSION="$(tmux display-message -p '#S' 2>/dev/null || true)"
    fi
    if [[ -z "$BYOBU_SESSION" ]]; then
        BYOBU_SESSION="$BYOBU_DEFAULT_SESSION"
        if ! byobu has-session -t "$BYOBU_SESSION" 2>/dev/null; then
            byobu new-session -d -s "$BYOBU_SESSION"
            ok "Sesión persistente '${BYOBU_SESSION}' creada."
        fi
    fi
}

# ── _setup_byobu_window ───────────────────────────────────────────────────────
# Crea la ventana 'sunshine' dentro de la sesión del usuario. Si ya existe,
# la reutiliza. Nunca crea ni mata sesiones.
_setup_byobu_window() {
    _resolve_session
    if byobu list-windows -t "$BYOBU_SESSION" -F '#{window_name}' 2>/dev/null \
        | grep -qx "$BYOBU_WINDOW"; then
        ok "Ventana byobu '${BYOBU_WINDOW}' ya existe — reutilizando."
        return 0
    fi
    byobu new-window -d -t "$BYOBU_SESSION" -n "$BYOBU_WINDOW"
    ok "Ventana byobu '${BYOBU_WINDOW}' creada en sesión '${BYOBU_SESSION}'."
}

# ── _launch_all_in_byobu ──────────────────────────────────────────────────────
# Crea los 4 panes capturando su pane-id REAL (estable), en vez de asumir
# índices 0..3 (que tmux no garantiza tras varios splits). Los ids se guardan
# en globales PANE_* para uso del watchdog/sunshine.
_launch_all_in_byobu() {
    local win="${BYOBU_SESSION}:${BYOBU_WINDOW}"
    local env_str
    env_str="export DISPLAY=${DISPLAY_NUM}; export XAUTHORITY=${REAL_HOME}/.Xauthority; \
export LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME}; export LIBVA_DRIVERS_PATH=${LIBVA_DRIVERS_PATH}"

    # Pane base (ya existe con la ventana).
    PANE_XORG=$(byobu list-panes -t "$win" -F '#{pane_id}' 2>/dev/null | head -1)

    # 4 panes en cuadrícula 2×2 (esquinas iguales). 'tiled' es el layout
    # estable de tmux para repartir N panes en rejilla uniforme.
    PANE_XORG=$(byobu list-panes -t "$win" -F '#{pane_id}' 2>/dev/null | head -1)
    PANE_I3=$(byobu split-window -t "$PANE_XORG" -P -F '#{pane_id}')
    PANE_SUNSHINE=$(byobu split-window -t "$PANE_I3" -P -F '#{pane_id}')
    PANE_WATCHDOG=$(byobu split-window -t "$PANE_SUNSHINE" -P -F '#{pane_id}')
    byobu select-layout -t "$win" tiled 2>/dev/null || true

    # Títulos de pane (printf en la propia shell del pane; sin escapes frágiles).
    byobu send-keys -t "$PANE_XORG" \
        "printf '\033]2;xorg-log\007'; echo '=== XORG LOG ==='; tail -f ${XORG_LOG}" Enter
    byobu send-keys -t "$PANE_I3" \
        "printf '\033]2;i3\007'; ${env_str}; echo '[i3] Arrancando...'; exec i3 2>&1" Enter
    byobu send-keys -t "$PANE_SUNSHINE" \
        "printf '\033]2;sunshine\007'; ${env_str}; echo '[sunshine] Arrancando...'; ${SUNSHINE_BIN} 2>&1 | tee ${SUNSHINE_LOG}" Enter

    # Exportar ids para watchdog/sunshine (lanzados luego).
    export PANE_XORG PANE_I3 PANE_SUNSHINE PANE_WATCHDOG

    ok "Layout 4 panes creado."

    # Esperar arranque inicial de i3 y Sunshine.
    log "Esperando arranque de i3 y Sunshine (4s)..."
    sleep 4

    local _i3_pid _sun_pid
    _i3_pid=$(pgrep -x i3 2>/dev/null | head -1 || true)
    _sun_pid=$(pgrep -x sunshine 2>/dev/null | head -1 || true)
    [[ -n "$_i3_pid" ]] \
        && ok "i3 corriendo (PID ${_i3_pid})." \
        || warn "i3 no detectado aún — revisar pane [i3]."
    [[ -n "$_sun_pid" ]] \
        && ok "Sunshine corriendo (PID ${_sun_pid})." \
        || warn "Sunshine no detectado aún — puede estar inicializando."

    # Generar y lanzar watchdog en su pane.
    generate_watchdog
    launch_watchdog

    byobu select-pane -t "$PANE_WATCHDOG" 2>/dev/null || true
}

# ── _print_summary ────────────────────────────────────────────────────────────
_print_summary() {
    divider
    echo -e "${GREEN}${BOLD}  ${SYM_OK} Sistema en ejecución — v9.0-PROD${RESET}"
    divider
    echo ""
    echo -e "  ${BOLD}Panes:${RESET}  xorg-log · i3 · sunshine  +  watchdog (abajo)"
    echo ""
    echo -e "  ${BOLD}Web UI :${RESET}  ${CYAN}https://localhost:47990${RESET}"
    echo -e "  ${BOLD}Ventana:${RESET}  '${BYOBU_WINDOW}' en sesión '${BYOBU_SESSION}'"
    echo -e "  ${BOLD}Ir     :${RESET}  Ctrl+B + W  (lista de ventanas)"
    echo -e "  ${BOLD}Panes  :${RESET}  Ctrl+B + flechas   ·   Zoom: Ctrl+B + Z"
    echo ""
    echo -e "  ${DIM}Logs : ${WATCHDOG_LOG}${RESET}"
    echo -e "  ${DIM}X11  : ${XORG_LOG}${RESET}"
    echo ""
}

# =============================================================================
# CMD_STOP
# =============================================================================
cmd_stop() {
    local force_xorg=0
    [[ "${1:-}" == "--force-xorg" ]] && force_xorg=1

    local _mode
    if (( force_xorg )); then _mode="full (incluye X11)"; else _mode="conserva X11"; fi
    banner "Sunshine Stop" "modo: ${_mode}"

    stop_watchdog

    # Cerrar SOLO la ventana 'sunshine' del script — nunca la sesión ni tus
    # otras ventanas. La sesión es del usuario y se conserva siempre.
    _resolve_session
    if byobu list-windows -t "$BYOBU_SESSION" -F '#{window_name}' 2>/dev/null \
        | grep -qx "$BYOBU_WINDOW"; then
        log "Cerrando ventana byobu '${BYOBU_WINDOW}' (sesión '${BYOBU_SESSION}' intacta)..."
        byobu kill-window -t "${BYOBU_SESSION}:${BYOBU_WINDOW}" 2>/dev/null || true
        ok "Ventana '${BYOBU_WINDOW}' cerrada."
    else
        log "Ventana '${BYOBU_WINDOW}' no existe — nada que cerrar."
    fi

    stop_sunshine

    pkill -TERM i3 2>/dev/null && ok "i3 detenido." || true

    if (( force_xorg )); then
        stop_x11
    else
        log "X11 conservado (usa --force-xorg para detenerlo)."
    fi

    ok "Stop completado."
}

# =============================================================================
# CMD_RESTART  — solo reinicia Sunshine; X11/i3/byobu intocables
# =============================================================================
cmd_restart() {
    banner "Sunshine Restart" "Solo Sunshine — X11/i3/byobu intactos"
    restart_sunshine
}

# =============================================================================
# CMD_STATUS
# =============================================================================
cmd_status() {
    banner "Estado del sistema" "$(date '+%Y-%m-%d %H:%M:%S')"

    local name pid
    for name in Xorg i3 sunshine; do
        pid=$(pgrep -x "$name" 2>/dev/null | head -1 || true)
        if [[ -n "$pid" ]]; then
            ok "${name}     : ${GREEN}CORRIENDO${RESET} (PID ${pid})"
        else
            warn "${name}     : ${RED}DETENIDO${RESET}"
        fi
    done

    local wd_pid
    if watchdog_running; then
        wd_pid=$(cat "$PID_FILE" 2>/dev/null || true)
        ok "Watchdog  : ${GREEN}ACTIVO${RESET} (PID ${wd_pid}, cada ${WATCHDOG_INTERVAL}s)"
    else
        warn "Watchdog  : ${RED}INACTIVO${RESET}"
    fi

    divider

    _resolve_session
    if byobu list-windows -t "$BYOBU_SESSION" -F '#{window_name}' 2>/dev/null \
        | grep -qx "$BYOBU_WINDOW"; then
        ok "Byobu     : ventana '${BYOBU_WINDOW}' activa (sesión '${BYOBU_SESSION}')"
        echo ""
        byobu list-panes -t "${BYOBU_SESSION}:${BYOBU_WINDOW}" \
            -F "  pane #{pane_index}: #{pane_title} (PID #{pane_pid})" 2>/dev/null || true
    else
        warn "Byobu     : ventana '${BYOBU_WINDOW}' no encontrada"
    fi
    echo ""
}

# =============================================================================
# CMD_LOGS
# =============================================================================
cmd_logs() {
    local target="${1:-watchdog}"
    case "$target" in
        watchdog) tail -f "$WATCHDOG_LOG" ;;
        sunshine) tail -f "$SUNSHINE_LOG" ;;
        xorg)     tail -f "$XORG_LOG" ;;
        *)
            warn "Logs disponibles: watchdog | sunshine | xorg"
            echo "  Ejemplo: $0 logs sunshine"
            ;;
    esac
}

# =============================================================================
# USAGE
# =============================================================================
_usage() {
    banner "Sunshine Runner  v9.0-PROD" "Gestión del servidor de streaming headless"
    echo -e "  ${BOLD}Uso:${RESET}"
    echo -e "    ${CYAN}$0 start${RESET}                    Enciende X11 + i3 + Sunshine + watchdog"
    echo -e "    ${CYAN}$0 stop${RESET}                     Apaga Sunshine/watchdog; conserva X11"
    echo -e "    ${CYAN}$0 stop --force-xorg${RESET}        Apaga todo incluyendo X11"
    echo -e "    ${CYAN}$0 restart${RESET}                  Reinicia SOLO Sunshine"
    echo -e "    ${CYAN}$0 status${RESET}                   Estado de todos los procesos"
    echo -e "    ${CYAN}$0 logs [watchdog|sunshine|xorg]${RESET}"
    echo ""
    echo -e "  ${DIM}Vars de entorno: DISPLAY_NUM, VT_NUM, SUNSHINE_BIN, WATCHDOG_INTERVAL${RESET}"
    echo ""
    exit 1
}

# =============================================================================
# DISPATCHER
# =============================================================================
case "${1:-}" in
    start)   cmd_start                ;;
    stop)    cmd_stop "${2:-}"        ;;
    restart) cmd_restart              ;;
    status)  cmd_status               ;;
    logs)    cmd_logs "${2:-}"        ;;
    *)       _usage                   ;;
esac
