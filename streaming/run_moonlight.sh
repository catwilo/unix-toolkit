#!/usr/bin/env bash
# =============================================================================
# run_moonlight.sh — Cliente Moonlight Qt
# Versión: 3.0-PROD
#
# Uso:
#   ./run_moonlight.sh start [HOST]  → Lanza Moonlight (HOST opcional)
#   ./run_moonlight.sh stop          → Cierra Moonlight
#   ./run_moonlight.sh status        → Estado
# =============================================================================
set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/moonlight.sh"

# =============================================================================
# CONFIGURACIÓN
# =============================================================================
MOONLIGHT_BIN="${MOONLIGHT_BIN:-moonlight-qt}"
MOONLIGHT_LOG="${MOONLIGHT_LOG:-/tmp/moonlight_run.log}"
SUNSHINE_HOST="${SUNSHINE_HOST:-}"   # vacío = mDNS automático
LOG_FILE="${LOG_FILE:-/tmp/run_moonlight.log}"

[[ $EUID -eq 0 ]] && fail "NO ejecutes como root."

# =============================================================================
# CMD_START
# =============================================================================
cmd_start() {
    [[ -n "${1:-}" ]] && SUNSHINE_HOST="$1"

    banner "Moonlight Qt  v3.0-PROD" "host=${SUNSHINE_HOST:-mDNS automático}"

    step 1 3 "Verificando entorno"
    preflight_moonlight || fail "Preflight fallido."

    step 2 3 "Verificando conectividad"
    check_connectivity

    step 3 3 "Lanzando Moonlight"
    start_moonlight

    divider
    echo -e "${GREEN}${BOLD}  ${SYM_OK} Moonlight Qt en ejecución${RESET}"
    divider
    echo ""
    echo -e "  ${BOLD}Pasos en la UI:${RESET}"
    echo -e "    1. El servidor Sunshine aparece automáticamente"
    echo -e "    2. Clic en el servidor → emparejamiento"
    echo -e "    3. Introduce el PIN en: ${CYAN}https://<IP-servidor>:47990${RESET}"
    echo -e "    4. Selecciona aplicación o escritorio"
    echo ""
    echo -e "  ${DIM}Log: ${MOONLIGHT_LOG}${RESET}"
    echo -e "  ${DIM}Detener: $0 stop${RESET}"
    echo ""
}

# =============================================================================
# CMD_STOP
# =============================================================================
cmd_stop() {
    banner "Moonlight Stop"
    stop_moonlight
}

# =============================================================================
# CMD_STATUS
# =============================================================================
cmd_status() {
    banner "Moonlight Status"
    if moonlight_running; then
        local _pid; _pid=$(pgrep -x moonlight-qt 2>/dev/null | head -1 || true)
        ok "moonlight-qt : ${GREEN}CORRIENDO${RESET} (PID ${_pid})"
    else
        warn "moonlight-qt : ${RED}DETENIDO${RESET}"
    fi
    echo ""
}

# =============================================================================
# USAGE
# =============================================================================
_usage() {
    banner "Moonlight Qt  v3.0-PROD"
    echo -e "  ${CYAN}$0 start [HOST]${RESET}   Lanza Moonlight (HOST opcional)"
    echo -e "  ${CYAN}$0 stop${RESET}            Cierra Moonlight"
    echo -e "  ${CYAN}$0 status${RESET}          Estado del proceso"
    echo ""
    exit 1
}

case "${1:-}" in
    start)  cmd_start "${2:-}" ;;
    stop)   cmd_stop           ;;
    status) cmd_status         ;;
    *)      _usage             ;;
esac
