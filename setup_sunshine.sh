#!/usr/bin/env bash
# =============================================================================
# setup_sunshine.sh — Instalación inicial del entorno Sunshine/i3/VAAPI
# Versión: 4.1-PROD | Ejecución: UNA SOLA VEZ tras instalación del SO
# Uso: sudo ./setup_sunshine.sh
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

LOG_FILE="/var/log/setup_sunshine.log"
touch "$LOG_FILE"; chmod 644 "$LOG_FILE"

log()  { echo -e "${CYAN}[INFO]${RESET}  $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "$LOG_FILE"; }
fail() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$LOG_FILE"; exit 1; }

[[ $EUID -ne 0 ]] && fail "Ejecuta con sudo: sudo ./setup_sunshine.sh"
[[ -z "${SUDO_USER:-}" ]] && fail "Usa 'sudo ./setup_sunshine.sh', no 'su root'."

REAL_USER="$SUDO_USER"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
[[ -z "$REAL_HOME" ]]   && fail "No se pudo determinar el home de $REAL_USER"
[[ ! -d "$REAL_HOME" ]] && fail "El directorio home no existe: $REAL_HOME"

echo -e "\n${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Sunshine Setup — Headless GPU/VAAPI  v4.1-PROD${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}\n"
log "Usuario: $REAL_USER | Home: $REAL_HOME | Log: $LOG_FILE"

# ─── STEP 1: DEPENDENCIAS ─────────────────────────────────────────────────────
echo -e "\n${BOLD}[1/7] Instalando dependencias base...${RESET}"
apt-get update -qq >> "$LOG_FILE" 2>&1
(
    apt-get install -y --no-install-recommends \
        xorg x11-xserver-utils xauth i3 \
        vainfo intel-media-va-driver-non-free mesa-va-drivers \
        libva2 libva-drm2 libva-x11-2 \
        dbus-x11 byobu tmux curl jq
) >> "$LOG_FILE" 2>&1 || fail "Falló instalación de dependencias. Ver: $LOG_FILE"
ok "Dependencias instaladas."

# ─── STEP 2: SUNSHINE ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}[2/7] Verificando/Instalando Sunshine...${RESET}"
if dpkg -s sunshine &>/dev/null; then
    ok "Sunshine ya instalado ($(dpkg-query -W -f='${Version}' sunshine 2>/dev/null)). Saltando."
else
    DEB_PATH=""
    for candidate in \
        "./sunshine-debian-trixie-amd64.deb" \
        "$REAL_HOME/sunshine-debian-trixie-amd64.deb" \
        "/tmp/sunshine-debian-trixie-amd64.deb"
    do
        [[ -f "$candidate" ]] && { DEB_PATH="$candidate"; break; }
    done
    if [[ -n "$DEB_PATH" ]]; then
        apt-get install -y "$DEB_PATH" >> "$LOG_FILE" 2>&1 \
            || fail "Falló instalación del .deb. Ver: $LOG_FILE"
        ok "Sunshine instalado desde: $DEB_PATH"
    else
        warn "No se encontró el .deb de Sunshine."
        warn "Descárgalo de: https://github.com/LizardByte/Sunshine/releases"
        warn "Colócalo junto a este script y re-ejecútalo."
    fi
fi

# ─── STEP 3: GRUPOS GPU + INPUT ───────────────────────────────────────────────
echo -e "\n${BOLD}[3/7] Configurando grupos GPU e input...${RESET}"
for grp in video render input; do
    if getent group "$grp" &>/dev/null; then
        usermod -aG "$grp" "$REAL_USER" >> "$LOG_FILE" 2>&1 \
            && ok "Grupo añadido: $grp" \
            || warn "No se pudo añadir grupo: $grp"
    else
        warn "Grupo '$grp' no existe (no crítico)."
    fi
done

# ─── STEP 4: UDEV uinput ──────────────────────────────────────────────────────
echo -e "\n${BOLD}[4/7] Configurando uinput (teclado/ratón virtual)...${RESET}"
cat > /etc/udev/rules.d/99-uinput.rules << 'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660"
EOF
modprobe uinput 2>/dev/null || true
chown root:input /dev/uinput 2>/dev/null || true
chmod 660 /dev/uinput 2>/dev/null || true
echo "uinput" > /etc/modules-load.d/uinput.conf
ok "uinput configurado y persistente."

# ─── STEP 5: XORG.CONF HEADLESS ───────────────────────────────────────────────
# Fuerza resolución 1366x768@60Hz en DP-1 sin monitor físico.
# InputClass wacom: silencia el error del dispositivo virtual de tableta
# que Sunshine crea via uinput (no es hardware real).
echo -e "\n${BOLD}[5/7] Configurando xorg.conf headless 1366x768@60Hz...${RESET}"
cat > /etc/X11/xorg.conf << 'EOF'
Section "Device"
    Identifier "Intel"
    Driver "modesetting"
    BusID "PCI:0:2:0"
    Option "VirtualHeads" "1"
EndSection

Section "Monitor"
    Identifier "DP-1"
    HorizSync 28-80
    VertRefresh 48-75
    Modeline "1366x768_60" 85.25 1366 1438 1574 1782 768 771 781 798 -hsync +vsync
    Option "Enable" "true"
    Option "Ignore" "false"
EndSection

Section "Screen"
    Identifier "Default Screen"
    Device "Intel"
    Monitor "DP-1"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1366x768_60"
        Virtual 1366 768
    EndSubSection
EndSection

Section "InputClass"
    Identifier "Ignore Wacom passthrough"
    MatchProduct "Pen passthrough"
    Option "Ignore" "true"
EndSection
EOF
ok "xorg.conf creado: 1366x768@60Hz + wacom silenciado."

# ─── STEP 6: CONFIG SUNSHINE ──────────────────────────────────────────────────
echo -e "\n${BOLD}[6/7] Configurando Sunshine...${RESET}"
SUNSHINE_CONF_DIR="$REAL_HOME/.config/sunshine"
mkdir -p "$SUNSHINE_CONF_DIR"
cat > "$SUNSHINE_CONF_DIR/sunshine.conf" << 'EOF'
# Sunshine config — generado por setup_sunshine.sh v4.1-PROD
encoder=vaapi
adapter_name=/dev/dri/renderD128
min_log_level=info
address=0.0.0.0
origin_web_ui_allowed=wan
EOF
chown -R "$REAL_USER:$REAL_USER" "$SUNSHINE_CONF_DIR"
ok "sunshine.conf configurado."

# ─── STEP 7: XWRAPPER ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}[7/7] Configurando Xwrapper...${RESET}"
cat > /etc/X11/Xwrapper.config << 'EOF'
allowed_users=console
needs_root_rights=yes
EOF
ok "Xwrapper configurado."

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  ✔ Setup completado — v4.1-PROD${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════════${RESET}"
echo -e "  Usuario  : $REAL_USER"
echo -e "  Grupos   : video, render, input"
echo -e "  uinput   : persistente"
echo -e "  xorg.conf: 1366x768@60Hz headless"
echo -e "  Config   : $SUNSHINE_CONF_DIR/sunshine.conf"
echo -e "  Log      : $LOG_FILE"
echo ""
warn "Los cambios de grupo requieren reinicio."
echo -e "${BOLD}👉 sudo reboot${RESET}\n"

