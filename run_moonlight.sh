#!/usr/bin/env bash
# =============================================================================
# run_moonlight.sh — Arranque del cliente Moonlight Qt
# Versión: 1.0-PROD | Ejecución: cada vez que quieras conectar al servidor
# Uso: ./run_moonlight.sh  (SIN sudo — como usuario normal)
#
# Requisitos previos:
#   - setup_moonlight.sh ejecutado y reinicio realizado
#   - Servidor Sunshine corriendo (host) con run_sunshine.sh
#   - Misma red o VPN entre cliente y servidor
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ─── COLORES ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── CONFIGURACIÓN ────────────────────────────────────────────────────────────
MOONLIGHT_BIN="moonlight-qt"
MOONLIGHT_LOG="/tmp/moonlight_run.log"

# IP del servidor Sunshine — cambiar si es estática o usar hostname
# Dejar vacío para que Moonlight descubra automáticamente via mDNS
SUNSHINE_HOST=""

# ─── LOGGING ──────────────────────────────────────────────────────────────────
log()  { echo -e "${CYAN}[INFO]${RESET}  $(date '+%H:%M:%S') $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $(date '+%H:%M:%S') $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $(date '+%H:%M:%S') $*"; }
fail() { echo -e "${RED}[ERROR]${RESET} $(date '+%H:%M:%S') $*"; exit 1; }

##!/usr/bin/env bash
# =============================================================================
# run_moonlight.sh — Lanzador de Moonlight Qt
# Versión: 2.0-PROD | Uso: ./run_moonlight.sh  (sin sudo)
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

MOONLIGHT_BIN="moonlight-qt"
MOONLIGHT_LOG="/tmp/moonlight_run.log"

# IP del servidor Sunshine — dejar vacío para descubrimiento automático vía mDNS
SUNSHINE_HOST=""

log()  { echo -e "${CYAN}[INFO]${RESET}  $(date '+%H:%M:%S') $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $(date '+%H:%M:%S') $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $(date '+%H:%M:%S') $*"; }
fail() { echo -e "${RED}[ERROR]${RESET} $(date '+%H:%M:%S') $*"; exit 1; }

[[ $EUID -eq 0 ]] && fail "NO ejecutes como root. Usa tu usuario normal."

echo -e "\n${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Moonlight Qt Runner — v2.0-PROD${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}\n"

# ─── STEP 1: VERIFICACIONES ───────────────────────────────────────────────────
echo -e "\n${BOLD}[1/3] Verificando entorno...${RESET}"

command -v "$MOONLIGHT_BIN" &>/dev/null \
    || fail "'$MOONLIGHT_BIN' no encontrado. ¿Ejecutaste setup_moonlight.sh y reiniciaste?"

for grp in video input; do
    id -nG "$USER" | grep -qw "$grp" \
        || warn "Usuario no está en grupo '$grp'. ¿Reiniciaste tras el setup?"
done

[[ -e /dev/dri/card0 ]] \
    && ok "GPU disponible: /dev/dri/card0" \
    || warn "/dev/dri/card0 no existe — se usará decodificación por CPU."

if [[ -n "${DISPLAY:-}" ]]; then
    ok "Backend gráfico: X11 ($DISPLAY)"
elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    ok "Backend gráfico: Wayland ($WAYLAND_DISPLAY)"
else
    warn "Sin sesión gráfica detectada — Moonlight intentará modo KMS/DRM directo."
fi

# ─── STEP 2: CONECTIVIDAD ─────────────────────────────────────────────────────
echo -e "\n${BOLD}[2/3] Verificando conectividad...${RESET}"

if [[ -n "$SUNSHINE_HOST" ]]; then
    ping -c 1 -W 2 "$SUNSHINE_HOST" &>/dev/null \
        && ok "Servidor alcanzable: $SUNSHINE_HOST" \
        || warn "No se pudo hacer ping a $SUNSHINE_HOST — Moonlight intentará conectar igualmente."

    if command -v nc &>/dev/null; then
        nc -z -w 3 "$SUNSHINE_HOST" 47989 2>/dev/null \
            && ok "Puerto 47989 abierto en $SUNSHINE_HOST" \
            || warn "Puerto 47989 no responde — ¿está corriendo run_sunshine.sh en el servidor?"
    fi
else
    log "SUNSHINE_HOST vacío — descubrimiento automático vía mDNS."
fi

# ─── STEP 3: LANZAR MOONLIGHT ─────────────────────────────────────────────────
echo -e "\n${BOLD}[3/3] Lanzando Moonlight Qt...${RESET}"

# Cerrar instancia previa si existe
if pgrep -x moonlight-qt &>/dev/null; then
    warn "Instancia previa detectada — cerrando..."
    pkill -TERM moonlight-qt 2>/dev/null || true
    sleep 2
    pkill -KILL moonlight-qt 2>/dev/null || true
    sleep 1
fi

if [[ -n "$SUNSHINE_HOST" ]]; then
    LAUNCH_CMD="$MOONLIGHT_BIN stream $SUNSHINE_HOST"
else
    LAUNCH_CMD="$MOONLIGHT_BIN"
fi

$LAUNCH_CMD > "$MOONLIGHT_LOG" 2>&1 &
MOONLIGHT_PID=$!
sleep 2

kill -0 "$MOONLIGHT_PID" 2>/dev/null || {
    warn "Moonlight terminó inmediatamente. Últimas líneas del log:"
    tail -10 "$MOONLIGHT_LOG" 2>/dev/null || true
    fail "Moonlight no arrancó. Ver: $MOONLIGHT_LOG"
}

ok "Moonlight Qt arrancado (PID: $MOONLIGHT_PID)"

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  ✔ Moonlight Qt en ejecución — v2.0-PROD${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "  PID    : $MOONLIGHT_PID"
echo -e "  Log    : $MOONLIGHT_LOG"
echo ""
echo -e "  ${BOLD}Pasos en la UI:${RESET}"
echo -e "    1. El servidor Sunshine aparecerá automáticamente"
echo -e "    2. Clic en el servidor → emparejamiento"
echo -e "    3. Introduce el PIN en: https://<IP-servidor>:47990"
echo -e "    4. Selecciona la aplicación o escritorio"
echo ""
echo -e "  Diagnóstico: tail -f $MOONLIGHT_LOG"
warn "Para detener: pkill moonlight-qt"
echo ""
# ─── VALIDACIONES PREVIAS ─────────────────────────────────────────────────────
