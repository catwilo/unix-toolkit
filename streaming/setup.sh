#!/usr/bin/env bash
# =============================================================================
# setup.sh — Instalador de Sunshine y/o Moonlight
#
# Uso:
#   sudo ./setup.sh                    → detecta entorno, hace preguntas, instala
#   sudo ./setup.sh sunshine
#   sudo ./setup.sh moonlight
#   sudo ./setup.sh both
#
# Arquitectura post-instalación:
#   ~/dev/streaming/          → scripts + libs (instalación permanente)
#   ~/.local/bin/sunshine     → wrapper invocable desde cualquier directorio
#   ~/.local/bin/moonlight    → ídem para moonlight
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

_ORIGINAL_ARGS=("$@")
export _ORIGINAL_ARGS

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/session.sh"

# =============================================================================
# CONFIGURACIÓN BASE
# =============================================================================
LOG_FILE="/var/log/streaming_setup.log"
MOONLIGHT_INSTALL_DIR="/opt/moonlight"

# Directorio de instalación de scripts (relativo al home del usuario real)
STREAMING_INSTALL_SUBDIR="dev/streaming"

# =============================================================================
# GUARDIA DE ROOT
# =============================================================================
[[ $EUID -ne 0 ]]       && fail "Ejecuta con sudo: sudo ./setup.sh [sunshine|moonlight|both]"
[[ -z "${SUDO_USER:-}" ]] && fail "Usa 'sudo ./setup.sh', no 'su root'."

REAL_USER="$SUDO_USER"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
[[ -z "$REAL_HOME" || ! -d "$REAL_HOME" ]] && fail "No se pudo determinar el home de ${REAL_USER}."

touch "$LOG_FILE"; chmod 644 "$LOG_FILE"

# Rutas derivadas (disponibles en todo el script)
STREAMING_INSTALL_DIR="${REAL_HOME}/${STREAMING_INSTALL_SUBDIR}"
LOCAL_BIN_DIR="${REAL_HOME}/.local/bin"

# =============================================================================
# FASE 0 — DETECCIÓN DE ENTORNO
# =============================================================================
session_detect
session_show_env
session_warn_if_risky

# =============================================================================
# FASE 1 — RECOLECCIÓN DE RESPUESTAS (todo antes de ejecutar nada)
# =============================================================================
_ARG_TARGET="${1:-}"

collect_all_answers() {
    local tty
    tty=$(_get_tty)

    banner "Configuración interactiva" \
           "Todas las preguntas primero — luego se instala sin interrupciones"

    # ── 1. Target ─────────────────────────────────────────────────────────────
    if [[ -n "$_ARG_TARGET" ]]; then
        case "$_ARG_TARGET" in
            sunshine|moonlight|both)
                CFG_TARGET="$_ARG_TARGET"
                log "Modo: ${BOLD}${CFG_TARGET}${RESET} (desde argumento)"
                ;;
            *)
                warn "Argumento inválido: '${_ARG_TARGET}'"
                pick CFG_TARGET "¿Qué deseas instalar?" \
                    "sunshine  — servidor de streaming headless (GPU/VAAPI)" \
                    "moonlight — cliente Qt para conectarse al servidor" \
                    "both      — instalar ambos en este equipo"
                CFG_TARGET="${CFG_TARGET%% *}"
                ;;
        esac
    else
        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Componentes ────────────────────────────────────────${RESET}" > "$tty"
        pick CFG_TARGET "¿Qué deseas instalar?" \
            "sunshine  — servidor de streaming headless (GPU/VAAPI)" \
            "moonlight — cliente Qt para conectarse al servidor" \
            "both      — instalar ambos en este equipo"
        CFG_TARGET="${CFG_TARGET%% *}"
    fi

    # ── 2. Directorio de instalación ──────────────────────────────────────────
    printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Directorio de instalación ─────────────────────────${RESET}" > "$tty"

    local _default_install="${REAL_HOME}/dev/streaming"
    ask_value CFG_INSTALL_DIR "Directorio de instalación" "$_default_install"

    # Normalizar: expandir ~ si el usuario lo escribió
    CFG_INSTALL_DIR="${CFG_INSTALL_DIR/#\~/$REAL_HOME}"

    if [[ -d "$CFG_INSTALL_DIR" ]]; then
        ok "Directorio existe — se actualizará el contenido."
    else
        log "Se creará: ${CFG_INSTALL_DIR}"
    fi

    # ── 3. Sunshine ───────────────────────────────────────────────────────────
    if [[ "$CFG_TARGET" == "sunshine" || "$CFG_TARGET" == "both" ]]; then

        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Sunshine — paquete ────────────────────────────────${RESET}" > "$tty"

        local _auto_deb=""
        local _deb_candidates=(
            "${SCRIPT_DIR}/sunshine-debian-trixie-amd64.deb"
            "${REAL_HOME}/sunshine-debian-trixie-amd64.deb"
            "/tmp/sunshine-debian-trixie-amd64.deb"
        )
        for _c in "${_deb_candidates[@]}"; do
            [[ -f "$_c" ]] && { _auto_deb="$(realpath "$_c")"; break; }
        done

        if dpkg -s sunshine &>/dev/null 2>&1; then
            local _ver; _ver=$(dpkg-query -W -f='${Version}' sunshine 2>/dev/null || echo "?")
            ok "Sunshine ya instalado (v${_ver}) — se saltará el paquete."
            CFG_SUNSHINE_DEB="already_installed"
        elif [[ -n "$_auto_deb" ]]; then
            ok "Encontrado .deb: ${_auto_deb}"
            local _use_found
            ask_yn _use_found "¿Usar este .deb?" "s"
            if [[ "$_use_found" == "s" ]]; then
                CFG_SUNSHINE_DEB="$_auto_deb"
            else
                ask_value CFG_SUNSHINE_DEB "Ruta completa al .deb (Enter = omitir)" ""
                [[ -z "$CFG_SUNSHINE_DEB" ]] && CFG_SUNSHINE_DEB="skip"
            fi
        else
            warn "No se encontró .deb de Sunshine automáticamente."
            printf '  %s\n' "${DIM}https://github.com/LizardByte/Sunshine/releases${RESET}" > "$tty"
            local _deb_choice
            pick _deb_choice "¿Qué hacer con el paquete Sunshine?" \
                "skip — ya instalado o lo instalaré manualmente" \
                "path — indico la ruta al .deb ahora"
            if [[ "$_deb_choice" == path* ]]; then
                ask_value CFG_SUNSHINE_DEB "Ruta completa al .deb" ""
                if [[ -n "$CFG_SUNSHINE_DEB" && ! -f "$CFG_SUNSHINE_DEB" ]]; then
                    warn "Archivo no encontrado — se omitirá."
                    CFG_SUNSHINE_DEB="skip"
                fi
            else
                CFG_SUNSHINE_DEB="skip"
            fi
        fi

        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Sunshine — pantalla virtual ───────────────────────${RESET}" > "$tty"
        ask_value CFG_DISPLAY_NUM "Número de DISPLAY X11"  ":0"
        ask_value CFG_VT_NUM      "Virtual Terminal (VT)"  "vt1"
        ask_value CFG_RESOLUTION  "Resolución headless"    "1920x1080"

        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Sunshine — aceleración de hardware ───────────────${RESET}" > "$tty"

        local _vainfo_out _gpu_ok="yes"
        _vainfo_out=$(vainfo 2>&1 || true)

        if   echo "$_vainfo_out" | grep -qi "iHD";             then CFG_GPU_DRIVER="iHD";      CFG_ENCODER="vaapi"; ok  "VAAPI detectado: iHD (Intel Media Driver)"
        elif echo "$_vainfo_out" | grep -qi "i965";            then CFG_GPU_DRIVER="i965";     CFG_ENCODER="vaapi"; ok  "VAAPI detectado: i965 (Intel legacy)"
        elif echo "$_vainfo_out" | grep -qi "radeonsi\|amdgpu";then CFG_GPU_DRIVER="radeonsi"; CFG_ENCODER="vaapi"; ok  "VAAPI detectado: AMD"
        elif command -v nvidia-smi &>/dev/null;                 then CFG_GPU_DRIVER="nvidia";   CFG_ENCODER="nvenc"; ok  "GPU NVIDIA detectada"
        else                                                         CFG_GPU_DRIVER="auto";     CFG_ENCODER="software"; _gpu_ok="no"
            warn "No se detectó GPU compatible — se usará encoder por software."
        fi

        if [[ "$_gpu_ok" == "yes" && "$CFG_ENCODER" == "vaapi" ]]; then
            local _h264 _hevc
            _h264=$(echo "$_vainfo_out" | grep -c "H264\|AVC"  2>/dev/null || echo 0)
            _hevc=$(echo "$_vainfo_out" | grep -c "HEVC\|H265" 2>/dev/null || echo 0)
            log "Perfiles VAAPI — H.264: ${_h264} | HEVC: ${_hevc}"
        fi

        local _confirm_enc
        ask_yn _confirm_enc \
            "Usar encoder=${BOLD}${CFG_ENCODER}${RESET} / driver=${BOLD}${CFG_GPU_DRIVER}${RESET} (auto-detectado)?" "s"
        if [[ "$_confirm_enc" == "n" ]]; then
            local _enc_choice
            pick _enc_choice "Encoder a usar:" \
                "vaapi    — Intel/AMD hardware (recomendado headless)" \
                "nvenc    — NVIDIA hardware" \
                "software — CPU (sin GPU)"
            CFG_ENCODER="${_enc_choice%% *}"
            [[ "$CFG_ENCODER" == "vaapi" ]] && \
                ask_value CFG_GPU_DRIVER "Driver VAAPI (iHD, i965, radeonsi...)" "$CFG_GPU_DRIVER"
        fi

        if    [[ -e /dev/dri/renderD128 ]]; then CFG_DRI_NODE="/dev/dri/renderD128"
        elif  [[ -e /dev/dri/renderD64  ]]; then CFG_DRI_NODE="/dev/dri/renderD64"; warn "renderD128 no encontrado — usando renderD64"
        else                                     CFG_DRI_NODE="/dev/dri/renderD128"; warn "Nodo DRI no encontrado — usando default"
        fi
    fi

    # ── 4. Moonlight ──────────────────────────────────────────────────────────
    if [[ "$CFG_TARGET" == "moonlight" || "$CFG_TARGET" == "both" ]]; then
        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Moonlight — versión ───────────────────────────────${RESET}" > "$tty"
        ask_value CFG_ML_VERSION "Versión de Moonlight Qt" "6.1.0"
    fi

    # ── 5. Resumen y confirmación ─────────────────────────────────────────────
    {
        banner "Resumen — lo que se va a instalar"
        printf '%s\n'     "  ${SYM_ARROW} ${BOLD}Componente${RESET}  : ${CFG_TARGET}"
        printf '%s\n'     "  ${SYM_ARROW} ${BOLD}Instalar en${RESET} : ${CFG_INSTALL_DIR}"
        printf '%s\n'     "  ${SYM_ARROW} ${BOLD}Wrappers${RESET}    : ${LOCAL_BIN_DIR}/sunshine  ${LOCAL_BIN_DIR}/moonlight"

        if [[ "$CFG_TARGET" == "sunshine" || "$CFG_TARGET" == "both" ]]; then
            printf '%s\n' "  ${SYM_ARROW} ${BOLD}Paquete${RESET}     : ${CFG_SUNSHINE_DEB}"
            printf '%s\n' "  ${SYM_ARROW} ${BOLD}Display${RESET}     : ${CFG_DISPLAY_NUM}  VT: ${CFG_VT_NUM}"
            printf '%s\n' "  ${SYM_ARROW} ${BOLD}Resolución${RESET}  : ${CFG_RESOLUTION}"
            printf '%s\n' "  ${SYM_ARROW} ${BOLD}Encoder${RESET}     : ${CFG_ENCODER}  (driver: ${CFG_GPU_DRIVER})"
            printf '%s\n' "  ${SYM_ARROW} ${BOLD}DRI node${RESET}    : ${CFG_DRI_NODE:-/dev/dri/renderD128}"
        fi

        if [[ "$CFG_TARGET" == "moonlight" || "$CFG_TARGET" == "both" ]]; then
            printf '%s\n' "  ${SYM_ARROW} ${BOLD}Moonlight${RESET}   : v${CFG_ML_VERSION}"
        fi

        printf '%s\n'   "  ${SYM_ARROW} ${BOLD}Log${RESET}         : ${LOG_FILE}"
        printf '%s\n'   "  ${SYM_ARROW} ${BOLD}Usuario${RESET}     : ${REAL_USER}"
        printf '\n%s\n' "  ${DIM}A partir de aquí corre sin más preguntas.${RESET}"
        printf '%s\n\n' "  ${DIM}Duración estimada: 2-5 minutos.${RESET}"
    } > "$tty"

    local _go
    ask_yn _go "¿Proceder con la instalación?" "s"
    [[ "$_go" != "s" ]] && { printf '\n%s\n\n' "${YELLOW}  Cancelado.${RESET}"; exit 0; }

    export CFG_TARGET CFG_INSTALL_DIR CFG_SUNSHINE_DEB \
           CFG_DISPLAY_NUM CFG_VT_NUM CFG_GPU_DRIVER \
           CFG_DRI_NODE CFG_RESOLUTION CFG_ENCODER CFG_ML_VERSION

    ok "Configuración confirmada — iniciando instalación..."
    printf '\n'
}

# =============================================================================
# FASE 2 — INSTALACIÓN DE SISTEMA (apt, grupos, udev, xorg, etc.)
# =============================================================================

_install_base_deps() {
    apt-get update -qq >> "$LOG_FILE" 2>&1
}

install_sunshine() {
    local total=7
    banner "Sunshine — instalación del sistema" "paquetes, grupos, udev, xorg, config"

    step 1 $total "Instalando dependencias del sistema"
    _install_base_deps
    apt-get install -y --no-install-recommends \
        xorg x11-xserver-utils xauth i3 \
        vainfo intel-media-va-driver-non-free mesa-va-drivers \
        libva2 libva-drm2 libva-x11-2 \
        dbus-x11 byobu tmux curl jq \
        >> "$LOG_FILE" 2>&1 \
        || fail "Falló instalación de dependencias. Ver: ${LOG_FILE}"
    ok "Dependencias instaladas."

    step 2 $total "Instalando paquete Sunshine"
    case "$CFG_SUNSHINE_DEB" in
        already_installed) ok "Ya instalado — saltando." ;;
        skip)              warn "Paquete omitido por configuración." ;;
        *)
            if [[ -f "$CFG_SUNSHINE_DEB" ]]; then
                apt-get install -y "$CFG_SUNSHINE_DEB" >> "$LOG_FILE" 2>&1 \
                    || fail "Falló instalación del .deb. Ver: ${LOG_FILE}"
                ok "Sunshine instalado desde: ${CFG_SUNSHINE_DEB}"
            else
                warn "Ruta .deb no válida — omitiendo."
            fi
            ;;
    esac

    step 3 $total "Configurando grupos (video, render, input)"
    for grp in video render input; do
        if getent group "$grp" &>/dev/null; then
            usermod -aG "$grp" "$REAL_USER" >> "$LOG_FILE" 2>&1 \
                && ok "Grupo añadido: ${grp}" \
                || warn "No se pudo añadir grupo: ${grp}"
        else
            warn "Grupo '${grp}' no existe (no crítico)."
        fi
    done

    step 4 $total "Configurando uinput (teclado/ratón virtual)"
    cat > /etc/udev/rules.d/99-uinput.rules << 'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660"
EOF
    modprobe uinput 2>/dev/null || true
    chown root:input /dev/uinput 2>/dev/null || true
    chmod 660 /dev/uinput 2>/dev/null || true
    echo "uinput" > /etc/modules-load.d/uinput.conf
    ok "uinput configurado y persistente."

    step 5 $total "Configurando xorg.conf headless (${CFG_RESOLUTION}@60Hz)"
    local _w _h _modeline=""
    IFS='x' read -r _w _h <<< "$CFG_RESOLUTION"

    if command -v cvt &>/dev/null; then
        local _cvt
        _cvt=$(cvt "$_w" "$_h" 60 2>/dev/null | grep Modeline || true)
        [[ -n "$_cvt" ]] && _modeline=$(echo "$_cvt" | sed 's/^[[:space:]]*Modeline //')
    fi
    if [[ -z "$_modeline" ]]; then
        case "$CFG_RESOLUTION" in
            1920x1080) _modeline='"1920x1080_60" 172.80 1920 2040 2248 2576 1080 1081 1084 1118 -hsync +vsync' ;;
            1280x720)  _modeline='"1280x720_60"  74.50  1280 1344 1472 1664 720  721  724  746  -hsync +vsync'  ;;
            *)         _modeline='"1366x768_60"  85.25  1366 1438 1574 1782 768  771  781  798  -hsync +vsync'  ;;
        esac
        warn "cvt no disponible — usando Modeline predefinida."
    fi
    local _mode_name
    _mode_name=$(echo "$_modeline" | awk '{print $1}' | tr -d '"')

    cat > /etc/X11/xorg.conf << EOF
Section "Device"
    Identifier "GPU"
    Driver "modesetting"
    BusID "PCI:0:2:0"
    Option "VirtualHeads" "1"
EndSection

Section "Monitor"
    Identifier "Virtual-Monitor"
    HorizSync 28-80
    VertRefresh 48-75
    Modeline ${_modeline}
    Option "Enable" "true"
EndSection

Section "Screen"
    Identifier "Default Screen"
    Device "GPU"
    Monitor "Virtual-Monitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "${_mode_name}"
        Virtual ${_w} ${_h}
    EndSubSection
EndSection

Section "InputClass"
    Identifier "Ignore Wacom passthrough"
    MatchProduct "Pen passthrough"
    Option "Ignore" "true"
EndSection
EOF
    ok "xorg.conf creado para ${CFG_RESOLUTION}@60Hz."

    step 6 $total "Configurando sunshine.conf"
    local conf_dir="${REAL_HOME}/.config/sunshine"
    mkdir -p "$conf_dir"
    local _dri="${CFG_DRI_NODE:-/dev/dri/renderD128}"
    cat > "${conf_dir}/sunshine.conf" << EOF
encoder=${CFG_ENCODER}
adapter_name=${_dri}
min_log_level=info
address=0.0.0.0
origin_web_ui_allowed=wan
EOF
    chown -R "${REAL_USER}:${REAL_USER}" "$conf_dir"
    ok "sunshine.conf — encoder=${CFG_ENCODER}  dri=${_dri}"

    step 7 $total "Configurando Xwrapper"
    cat > /etc/X11/Xwrapper.config << 'EOF'
allowed_users=console
needs_root_rights=yes
EOF
    ok "Xwrapper configurado."
}

install_moonlight() {
    local total=4
    banner "Moonlight — instalación del sistema" "AppImage v${CFG_ML_VERSION}"

    step 1 $total "Instalando dependencias"
    _install_base_deps
    apt-get install -y --no-install-recommends \
        curl wget ca-certificates libfuse2t64 \
        >> "$LOG_FILE" 2>&1 \
        || fail "Falló instalación de dependencias. Ver: ${LOG_FILE}"
    ok "Dependencias listas."

    step 2 $total "Descargando AppImage de Moonlight v${CFG_ML_VERSION}"
    local appimage_file="Moonlight-${CFG_ML_VERSION}-x86_64.AppImage"
    local dl_url="https://github.com/moonlight-stream/moonlight-qt/releases/download/v${CFG_ML_VERSION}/${appimage_file}"
    local appimage_path="${MOONLIGHT_INSTALL_DIR}/${appimage_file}"
    mkdir -p "$MOONLIGHT_INSTALL_DIR"

    if [[ -f "$appimage_path" ]]; then
        ok "AppImage ya existe — saltando descarga."
    else
        log "Descargando ${appimage_file}..."
        wget --show-progress -q "$dl_url" -O "$appimage_path" \
            || { rm -f "$appimage_path"; fail "Falló la descarga. URL: ${dl_url}"; }
        ok "Descargado: ${appimage_path}"
    fi
    chmod +x "$appimage_path"

    step 3 $total "Creando lanzador /usr/local/bin/moonlight-qt"
    cat > /usr/local/bin/moonlight-qt << EOF
#!/usr/bin/env bash
exec "${appimage_path}" --appimage-extract-and-run "\$@"
EOF
    chmod +x /usr/local/bin/moonlight-qt
    ok "Lanzador del sistema: /usr/local/bin/moonlight-qt"

    step 4 $total "Configurando grupos"
    for grp in video input; do
        if getent group "$grp" &>/dev/null; then
            usermod -aG "$grp" "$REAL_USER" >> "$LOG_FILE" 2>&1 \
                && ok "Grupo añadido: ${grp}" \
                || warn "No se pudo añadir grupo: ${grp}"
        else
            warn "Grupo '${grp}' no existe."
        fi
    done
}

# =============================================================================
# FASE 3 — INSTALACIÓN DE SCRIPTS EN ~/dev/streaming/
# =============================================================================

install_scripts() {
    banner "Instalando scripts" "${CFG_INSTALL_DIR}"

    step 1 3 "Preparando directorio ${CFG_INSTALL_DIR}"

    # Crear directorio si no existe
    if [[ ! -d "$CFG_INSTALL_DIR" ]]; then
        mkdir -p "$CFG_INSTALL_DIR"
        log "Creado: ${CFG_INSTALL_DIR}"
    else
        ok "Directorio ya existe — actualizando contenido."
    fi
    mkdir -p "${CFG_INSTALL_DIR}/lib"

    # Copiar siempre los libs (colors, session, x11, watchdog, sunshine lib, moonlight lib)
    cp "${SCRIPT_DIR}/lib/colors.sh"  "${CFG_INSTALL_DIR}/lib/"
    cp "${SCRIPT_DIR}/lib/session.sh" "${CFG_INSTALL_DIR}/lib/"
    cp "${SCRIPT_DIR}/lib/x11.sh"     "${CFG_INSTALL_DIR}/lib/"
    cp "${SCRIPT_DIR}/lib/watchdog.sh" "${CFG_INSTALL_DIR}/lib/"

    # Copiar scripts según el target instalado
    case "$CFG_TARGET" in
        sunshine)
            cp "${SCRIPT_DIR}/lib/sunshine.sh" "${CFG_INSTALL_DIR}/lib/"
            cp "${SCRIPT_DIR}/run_sunshine.sh"  "${CFG_INSTALL_DIR}/"
            chmod +x "${CFG_INSTALL_DIR}/run_sunshine.sh"
            ;;
        moonlight)
            cp "${SCRIPT_DIR}/lib/moonlight.sh" "${CFG_INSTALL_DIR}/lib/"
            cp "${SCRIPT_DIR}/run_moonlight.sh"  "${CFG_INSTALL_DIR}/"
            chmod +x "${CFG_INSTALL_DIR}/run_moonlight.sh"
            ;;
        both)
            cp "${SCRIPT_DIR}/lib/sunshine.sh"  "${CFG_INSTALL_DIR}/lib/"
            cp "${SCRIPT_DIR}/lib/moonlight.sh" "${CFG_INSTALL_DIR}/lib/"
            cp "${SCRIPT_DIR}/run_sunshine.sh"   "${CFG_INSTALL_DIR}/"
            cp "${SCRIPT_DIR}/run_moonlight.sh"  "${CFG_INSTALL_DIR}/"
            chmod +x "${CFG_INSTALL_DIR}/run_sunshine.sh"
            chmod +x "${CFG_INSTALL_DIR}/run_moonlight.sh"
            ;;
    esac

    # Permisos correctos: el dueño es el usuario real, no root
    chown -R "${REAL_USER}:${REAL_USER}" "$CFG_INSTALL_DIR"
    ok "Scripts copiados y permisos establecidos."

    # ── Inyectar CFG_ en los scripts instalados ────────────────────────────────
    # run_sunshine.sh tiene defaults que se pueden sobreescribir por env.
    # Creamos un archivo .env junto a los scripts con los valores configurados.
    step 2 3 "Guardando configuración en ${CFG_INSTALL_DIR}/.env"

    cat > "${CFG_INSTALL_DIR}/.env" << EOF
# Generado por setup.sh — $(date '+%Y-%m-%d %H:%M:%S')
# Edita este archivo para cambiar la configuración sin re-ejecutar el setup.
DISPLAY_NUM="${CFG_DISPLAY_NUM:-:0}"
VT_NUM="${CFG_VT_NUM:-vt1}"
LIBVA_DRIVER_NAME="${CFG_GPU_DRIVER:-iHD}"
LIBVA_DRIVERS_PATH="/usr/lib/x86_64-linux-gnu/dri"
MOONLIGHT_VERSION="${CFG_ML_VERSION:-6.1.0}"
EOF
    chown "${REAL_USER}:${REAL_USER}" "${CFG_INSTALL_DIR}/.env"
    ok ".env guardado."

    # ── Crear wrappers en ~/.local/bin/ ───────────────────────────────────────
    step 3 3 "Creando wrappers en ${LOCAL_BIN_DIR}/"

    mkdir -p "$LOCAL_BIN_DIR"

    if [[ "$CFG_TARGET" == "sunshine" || "$CFG_TARGET" == "both" ]]; then
        cat > "${LOCAL_BIN_DIR}/sunshine" << EOF
#!/usr/bin/env bash
# Wrapper — generado por setup.sh
# Delega en: ${CFG_INSTALL_DIR}/run_sunshine.sh
set -euo pipefail
STREAMING_DIR="${CFG_INSTALL_DIR}"
ENV_FILE="\${STREAMING_DIR}/.env"
[[ -f "\$ENV_FILE" ]] && set -a && source "\$ENV_FILE" && set +a
exec "\${STREAMING_DIR}/run_sunshine.sh" "\$@"
EOF
        chmod +x "${LOCAL_BIN_DIR}/sunshine"
        chown "${REAL_USER}:${REAL_USER}" "${LOCAL_BIN_DIR}/sunshine"
        ok "Wrapper creado: ${LOCAL_BIN_DIR}/sunshine"
    fi

    if [[ "$CFG_TARGET" == "moonlight" || "$CFG_TARGET" == "both" ]]; then
        cat > "${LOCAL_BIN_DIR}/moonlight" << EOF
#!/usr/bin/env bash
# Wrapper — generado por setup.sh
# Delega en: ${CFG_INSTALL_DIR}/run_moonlight.sh
set -euo pipefail
STREAMING_DIR="${CFG_INSTALL_DIR}"
ENV_FILE="\${STREAMING_DIR}/.env"
[[ -f "\$ENV_FILE" ]] && set -a && source "\$ENV_FILE" && set +a
exec "\${STREAMING_DIR}/run_moonlight.sh" "\$@"
EOF
        chmod +x "${LOCAL_BIN_DIR}/moonlight"
        chown "${REAL_USER}:${REAL_USER}" "${LOCAL_BIN_DIR}/moonlight"
        ok "Wrapper creado: ${LOCAL_BIN_DIR}/moonlight"
    fi

    # ── Asegurar ~/.local/bin en PATH ─────────────────────────────────────────
    _ensure_local_bin_in_path
}

# ── _ensure_local_bin_in_path ─────────────────────────────────────────────────
# Añade ~/.local/bin al PATH en .bashrc y .zshrc si no está ya presente.
# Lo hace como el usuario real (no root).
_ensure_local_bin_in_path() {
    local path_snippet='export PATH="$HOME/.local/bin:$PATH"'
    local added=0

    for rc in ".bashrc" ".zshrc" ".bash_profile"; do
        local rc_file="${REAL_HOME}/${rc}"
        [[ -f "$rc_file" ]] || continue

        if grep -q '\.local/bin' "$rc_file" 2>/dev/null; then
            ok "${rc}: ~/.local/bin ya está en PATH."
        else
            printf '\n# Streaming tools\n%s\n' "$path_snippet" >> "$rc_file"
            chown "${REAL_USER}:${REAL_USER}" "$rc_file"
            ok "${rc}: añadido ~/.local/bin al PATH."
            added=1
        fi
    done

    # Si no existe ningún rc, usar .bashrc
    if [[ ! -f "${REAL_HOME}/.bashrc" && ! -f "${REAL_HOME}/.zshrc" ]]; then
        printf '# Streaming tools\n%s\n' "$path_snippet" >> "${REAL_HOME}/.bashrc"
        chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.bashrc"
        ok ".bashrc creado con PATH correcto."
        added=1
    fi

    if [[ "$added" -eq 1 ]]; then
        warn "PATH actualizado — tendrás que abrir una nueva terminal o ejecutar:"
        warn "  source ~/.bashrc"
    fi

    # También exportar para la sesión actual de sudo
    export PATH="${LOCAL_BIN_DIR}:${PATH}"
}

# =============================================================================
# FASE 4 — RESUMEN FINAL CON COMANDOS DISPONIBLES
# =============================================================================

print_final_summary() {
    divider

    printf '%s\n'   "${GREEN}${BOLD}  ${SYM_OK} Instalación completada${RESET}"
    printf '\n%s\n' "${BOLD}  Scripts instalados en:${RESET}  ${CFG_INSTALL_DIR}"
    printf '%s\n\n' "${BOLD}  Comandos disponibles:${RESET}"

    if [[ "$CFG_TARGET" == "sunshine" || "$CFG_TARGET" == "both" ]]; then
        printf '%s\n'   "  ${BOLD}${CYAN}sunshine${RESET}"
        printf '%s\n'   "    ${CYAN}sunshine start${RESET}                   Enciende X11 + i3 + Sunshine + watchdog"
        printf '%s\n'   "    ${CYAN}sunshine stop${RESET}                    Apaga Sunshine y watchdog (X11 intacto)"
        printf '%s\n'   "    ${CYAN}sunshine stop --force-xorg${RESET}       Apaga todo incluyendo X11"
        printf '%s\n'   "    ${CYAN}sunshine restart${RESET}                 Reinicia solo Sunshine"
        printf '%s\n'   "    ${CYAN}sunshine status${RESET}                  Estado de todos los procesos"
        printf '%s\n'   "    ${CYAN}sunshine logs${RESET}                    Log combinado (tail -f)"
        printf '%s\n'   "    ${CYAN}sunshine logs watchdog${RESET}           Solo log del watchdog"
        printf '%s\n'   "    ${CYAN}sunshine logs sunshine${RESET}           Solo log de Sunshine"
        printf '%s\n\n' "    ${CYAN}sunshine logs xorg${RESET}               Solo log de Xorg"
    fi

    if [[ "$CFG_TARGET" == "moonlight" || "$CFG_TARGET" == "both" ]]; then
        printf '%s\n'   "  ${BOLD}${CYAN}moonlight${RESET}"
        printf '%s\n'   "    ${CYAN}moonlight start${RESET}                  Lanza Moonlight (descubrimiento mDNS)"
        printf '%s\n'   "    ${CYAN}moonlight start 192.168.x.x${RESET}      Conecta directo a un host"
        printf '%s\n'   "    ${CYAN}moonlight stop${RESET}                   Cierra Moonlight"
        printf '%s\n\n' "    ${CYAN}moonlight status${RESET}                 Estado del proceso"
    fi

    printf '%s\n'   "  ${BOLD}Configuración:${RESET}  ${CFG_INSTALL_DIR}/.env"
    printf '%s\n'   "  ${BOLD}Log setup:${RESET}      ${LOG_FILE}"
    printf '\n'

    warn "Los cambios de grupo requieren cerrar y reabrir sesión (o reboot)."
    printf '%s\n\n' "${BOLD}${CYAN}  ${SYM_ARROW} sudo reboot${RESET}"

    divider
}

# =============================================================================
# MAIN
# =============================================================================

# Fase 1 — preguntas
collect_all_answers

# Fase 2 — instalación de sistema
banner "Instalando sistema" "target=${CFG_TARGET}  usuario=${REAL_USER}"
log "Log en: ${LOG_FILE}"

case "$CFG_TARGET" in
    sunshine) install_sunshine ;;
    moonlight) install_moonlight ;;
    both)     install_sunshine; printf '\n'; install_moonlight ;;
    *)        fail "Target inválido: '${CFG_TARGET}'" ;;
esac

# Fase 3 — instalar scripts + wrappers
install_scripts

# Fase 4 — resumen con comandos
print_final_summary
