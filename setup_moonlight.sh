#!/usr/bin/env bash
# =============================================================================
# setup_moonlight.sh — Instalación de Moonlight Qt (AppImage)
# Versión: 2.0-PROD | Idempotente — seguro de re-ejecutar
# Uso: sudo ./setup_moonlight.sh
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

LOG="/var/log/setup_moonlight.log"
touch "$LOG"; chmod 644 "$LOG"

log()  { echo -e "${CYAN}[INFO]${RESET}  $*" | tee -a "$LOG"; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $*" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "$LOG"; }
fail() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$LOG"; exit 1; }

[[ $EUID -ne 0 ]] && fail "Ejecuta con sudo: sudo ./setup_moonlight.sh"
[[ -z "${SUDO_USER:-}" ]] && fail "Usa 'sudo ./setup_moonlight.sh', no 'su root'."

REAL_USER="$SUDO_USER"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
[[ -z "$REAL_HOME" || ! -d "$REAL_HOME" ]] && fail "No se pudo determinar el home de $REAL_USER"

VERSION="6.1.0"
APPIMAGE_FILE="Moonlight-${VERSION}-x86_64.AppImage"
DL_URL="https://github.com/moonlight-stream/moonlight-qt/releases/download/v${VERSION}/${APPIMAGE_FILE}"
INSTALL_DIR="/opt/moonlight"
APPIMAGE_PATH="${INSTALL_DIR}/${APPIMAGE_FILE}"
LAUNCHER="/usr/local/bin/moonlight-qt"

echo -e "\n${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Moonlight Qt Setup — v${VERSION}  v2.0-PROD${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}\n"

# ─── STEP 1: DEPENDENCIAS ─────────────────────────────────────────────────────
echo -e "\n${BOLD}[1/4] Verificando dependencias...${RESET}"
apt-get update -qq >> "$LOG" 2>&1
apt-get install -y --no-install-recommends \
    curl wget ca-certificates libfuse2t64 >> "$LOG" 2>&1 \
    || fail "No se pudieron instalar las dependencias. Ver: $LOG"
ok "Dependencias listas."

# ─── STEP 2: APPIMAGE ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}[2/4] Verificando AppImage...${RESET}"
mkdir -p "$INSTALL_DIR"

if [[ -f "$APPIMAGE_PATH" ]]; then
    ok "AppImage ya existe — saltando descarga: $APPIMAGE_PATH"
else
    log "Descargando ${APPIMAGE_FILE}..."
    wget --show-progress -q "$DL_URL" -O "$APPIMAGE_PATH" \
        || { rm -f "$APPIMAGE_PATH"; fail "Falló la descarga. Verifica: ${DL_URL}"; }
    ok "Descargado en: $APPIMAGE_PATH"
fi
chmod +x "$APPIMAGE_PATH"

# ─── STEP 3: LANZADOR ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}[3/4] Verificando lanzador...${RESET}"
if [[ -f "$LAUNCHER" ]]; then
    ok "Lanzador ya existe — saltando: $LAUNCHER"
else
    tee "$LAUNCHER" > /dev/null << EOF
#!/usr/bin/env bash
exec "${APPIMAGE_PATH}" --appimage-extract-and-run "\$@"
EOF
    chmod +x "$LAUNCHER"
    ok "Lanzador creado: $LAUNCHER"
fi

# ─── STEP 4: GRUPOS ───────────────────────────────────────────────────────────
echo -e "\n${BOLD}[4/4] Configurando grupos...${RESET}"
for grp in video input; do
    if getent group "$grp" &>/dev/null; then
        usermod -aG "$grp" "$REAL_USER" >> "$LOG" 2>&1 \
            && ok "Grupo: $grp" \
            || warn "No se pudo añadir grupo: $grp"
    else
        warn "Grupo '$grp' no existe."
    fi
done

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  ✔ Moonlight Qt ${VERSION} listo — v2.0-PROD${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "  AppImage : $APPIMAGE_PATH"
echo -e "  Lanzador : $LAUNCHER"
echo -e "  Log      : $LOG"
echo ""
warn "Los cambios de grupo requieren reinicio."
echo -e "${BOLD}👉 sudo reboot${RESET}\n"

