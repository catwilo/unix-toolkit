#!/usr/bin/env bash
# =============================================================================
# lib/session.sh — Detección de entorno y recolección de configuración upfront
# Versión: 1.0-PROD
#
# Detecta:
#   - Tipo de sesión: SSH / local tty / tmux / screen / sin tty
#   - Estabilidad: si hay riesgo de desconexión durante el setup
#   - Conexión SSH: host de origen, keepalive, si está dentro de tmux/screen
#
# Exporta:
#   SESSION_TYPE       → ssh | local | tmux_local | tmux_ssh | unknown
#   SESSION_SSH_CLIENT → IP del cliente SSH (o vacío)
#   SESSION_RISKY      → "yes" si hay riesgo de cuelgue por desconexión
#   SESSION_IN_MUXER  → "yes" si ya está dentro de tmux/screen/byobu
#
# Función principal:
#   session_detect        → detecta y muestra banner de entorno
#   session_warn_if_risky → avisa si la conexión es frágil, sugiere tmux
#   collect_all_answers   → hace TODAS las preguntas antes de ejecutar nada
# =============================================================================

# ── session_detect ────────────────────────────────────────────────────────────
session_detect() {
    SESSION_TYPE="unknown"
    SESSION_SSH_CLIENT="${SSH_CLIENT:-${SSH_CONNECTION:-}}"
    SESSION_RISKY="no"
    SESSION_IN_MUXER="no"

    # ¿Estamos dentro de tmux/byobu/screen?
    if [[ -n "${TMUX:-}" ]] || [[ -n "${BYOBU_BACKEND:-}" ]]; then
        SESSION_IN_MUXER="yes"
    elif [[ -n "${STY:-}" ]]; then   # GNU screen
        SESSION_IN_MUXER="yes"
    fi

    # Tipo de conexión
    if [[ -n "${SSH_CLIENT:-}${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
        if [[ "$SESSION_IN_MUXER" == "yes" ]]; then
            SESSION_TYPE="tmux_ssh"
        else
            SESSION_TYPE="ssh"
            SESSION_RISKY="yes"   # SSH sin multiplexor: riesgo de cuelgue
        fi
    else
        if [[ "$SESSION_IN_MUXER" == "yes" ]]; then
            SESSION_TYPE="tmux_local"
        elif [[ -t 0 && -t 1 ]]; then
            SESSION_TYPE="local"
        fi
    fi

    export SESSION_TYPE SESSION_SSH_CLIENT SESSION_RISKY SESSION_IN_MUXER
}

# ── session_show_env ──────────────────────────────────────────────────────────
# Muestra un resumen visual del entorno detectado.
session_show_env() {
    local tty
    tty=$(_get_tty)

    {
        printf '\n%s\n' "${BOLD}${CYAN}  ── Entorno de sesión detectado ──────────────────────${RESET}"

        # Tipo de sesión
        case "$SESSION_TYPE" in
            local)
                printf '%s\n' "  ${GREEN}${SYM_OK}${RESET}  Sesión: ${BOLD}terminal local${RESET}"
                ;;
            ssh)
                local src="${SESSION_SSH_CLIENT%% *}"   # solo la IP
                printf '%s\n' "  ${YELLOW}${SYM_WARN}${RESET}  Sesión: ${BOLD}SSH sin multiplexor${RESET}  ${DIM}(origen: ${src:-desconocido})${RESET}"
                ;;
            tmux_local)
                printf '%s\n' "  ${GREEN}${SYM_OK}${RESET}  Sesión: ${BOLD}tmux/byobu local${RESET}"
                ;;
            tmux_ssh)
                local src="${SESSION_SSH_CLIENT%% *}"
                printf '%s\n' "  ${GREEN}${SYM_OK}${RESET}  Sesión: ${BOLD}SSH dentro de tmux/byobu${RESET}  ${DIM}(origen: ${src:-desconocido})${RESET}"
                ;;
            *)
                printf '%s\n' "  ${DIM}${SYM_INFO}  Sesión: tipo no determinado${RESET}"
                ;;
        esac

        # DISPLAY / Wayland
        if [[ -n "${DISPLAY:-}" ]]; then
            printf '%s\n' "  ${GREEN}${SYM_OK}${RESET}  DISPLAY activo: ${BOLD}${DISPLAY}${RESET}"
        elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
            printf '%s\n' "  ${CYAN}${SYM_INFO}${RESET}  Wayland activo: ${BOLD}${WAYLAND_DISPLAY}${RESET}"
        else
            printf '%s\n' "  ${DIM}${SYM_INFO}  Sin DISPLAY/Wayland (headless — esperado)${RESET}"
        fi

        # GPU
        if [[ -e /dev/dri/renderD128 ]]; then
            printf '%s\n' "  ${GREEN}${SYM_OK}${RESET}  GPU: ${BOLD}/dev/dri/renderD128${RESET} disponible"
        elif [[ -e /dev/dri/card0 ]]; then
            printf '%s\n' "  ${YELLOW}${SYM_WARN}${RESET}  GPU: solo ${BOLD}/dev/dri/card0${RESET} (renderD128 no encontrado)"
        else
            printf '%s\n' "  ${RED}${SYM_ERR}${RESET}  GPU: ${BOLD}ningún nodo DRI encontrado${RESET}"
        fi

        echo ""
    } > "$tty"
}

# ── session_warn_if_risky ─────────────────────────────────────────────────────
# Si la conexión es frágil (SSH sin tmux), avisa y pregunta cómo proceder.
# Exporta SETUP_USE_NOHUP="yes" si el usuario quiere protección extra.
session_warn_if_risky() {
    [[ "$SESSION_RISKY" != "yes" ]] && return 0

    local tty ans
    tty=$(_get_tty)

    {
        printf '%s\n' "${YELLOW}${BOLD}"
        printf '%s\n' "  ⚠  ATENCIÓN — Conexión SSH sin multiplexor"
        printf '%s\n' "${RESET}"
        printf '%s\n' "  Estás conectado por SSH sin tmux/byobu/screen."
        printf '%s\n' "  Si la conexión se cae durante el setup,"
        printf '%s\n' "  el proceso se interrumpirá en medio de la configuración."
        printf '%s\n' ""
        printf '%s\n' "  ${BOLD}Opciones:${RESET}"
        printf '%s\n' "    ${MAGENTA}[1]${RESET}  Crear sesión byobu automáticamente y continuar dentro"
        printf '%s\n' "    ${MAGENTA}[2]${RESET}  Continuar de todas formas (sin protección)"
        printf '%s\n' "    ${MAGENTA}[3]${RESET}  Cancelar — quiero conectarme desde un byobu/tmux"
        printf '%s\n' ""
    } > "$tty"

    local _choice
    pick _choice "¿Cómo quieres proceder?" \
        "Proteger — crear byobu y continuar dentro" \
        "Continuar igual (acepto el riesgo)" \
        "Cancelar — conectaré desde byobu/tmux"

    case "$_choice" in
        *"Proteger"*)
            warn "Relanzando dentro de byobu para proteger la sesión..."
            # Relanzar el script completo dentro de byobu
            local script_path
            script_path="$(realpath "${BASH_SOURCE[-1]}" 2>/dev/null || echo "$0")"
            local original_args=("${_ORIGINAL_ARGS[@]:-}")
            exec byobu new-session -s "streaming-setup" \
                "sudo bash '${script_path}' ${original_args[*]}; echo '— Pulsa Enter para cerrar —'; read"
            ;;
        *"Continuar"*)
            warn "Continuando sin protección. Asegúrate de no cortar la conexión."
            SETUP_USE_NOHUP="yes"
            export SETUP_USE_NOHUP
            ;;
        *"Cancelar"*)
            printf '\n%s\n' "${CYAN}  Cancelado. Conecta con byobu:${RESET}"
            printf '%s\n' "  ${BOLD}byobu${RESET}   (o: tmux new -s setup)"
            printf '%s\n' "  ${BOLD}sudo ./setup.sh${RESET}"
            exit 0
            ;;
    esac
}

# =============================================================================
# collect_all_answers
#
# Hace TODAS las preguntas de configuración ANTES de tocar el sistema.
# Guarda las respuestas en variables globales con prefijo CFG_.
#
# Variables exportadas:
#   CFG_TARGET          → sunshine | moonlight | both
#   CFG_SUNSHINE_DEB    → ruta al .deb (o "download" o "skip")
#   CFG_DISPLAY_NUM     → ej. ":0"
#   CFG_VT_NUM          → ej. "vt1"
#   CFG_GPU_DRIVER      → iHD | i965 | radeonsi | nvidia | auto
#   CFG_RESOLUTION      → ej. "1920x1080" o "1366x768"
#   CFG_ENCODER         → vaapi | nvenc | software
#   CFG_ML_VERSION      → versión de Moonlight (si aplica)
#   CFG_CONFIRMED       → "yes" cuando el usuario confirma todo
# =============================================================================
collect_all_answers() {
    local tty
    tty=$(_get_tty)

    banner "Configuración interactiva" "Todas las preguntas — luego se ejecuta sin interrupciones"

    # ── 1. Target ─────────────────────────────────────────────────────────────
    printf '%s\n' "${BOLD}${WHITE}  ┌─ ¿Qué deseas instalar? ─────────────────────────────${RESET}" > "$tty"
    pick CFG_TARGET "Selecciona el componente:" \
        "sunshine  — servidor de streaming headless (GPU/VAAPI)" \
        "moonlight — cliente Qt para conectarse al servidor" \
        "both      — instalar ambos en este equipo"
    # Extraer primera palabra
    CFG_TARGET="${CFG_TARGET%% *}"

    # ── 2. Preguntas específicas de Sunshine ──────────────────────────────────
    if [[ "$CFG_TARGET" == "sunshine" || "$CFG_TARGET" == "both" ]]; then

        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Sunshine — fuente de instalación ─────────────────${RESET}" > "$tty"

        # Buscar .deb automáticamente
        local _auto_deb=""
        local _deb_candidates=(
            "$(dirname "${BASH_SOURCE[-1]}")/../sunshine-debian-trixie-amd64.deb"
            "${HOME}/sunshine-debian-trixie-amd64.deb"
            "/tmp/sunshine-debian-trixie-amd64.deb"
        )
        for _c in "${_deb_candidates[@]}"; do
            [[ -f "$_c" ]] && { _auto_deb="$(realpath "$_c")"; break; }
        done

        if dpkg -s sunshine &>/dev/null 2>&1; then
            local _ver; _ver=$(dpkg-query -W -f='${Version}' sunshine 2>/dev/null || echo "?")
            ok "Sunshine ya instalado (v${_ver}) — se saltará la instalación del paquete."
            CFG_SUNSHINE_DEB="already_installed"
        elif [[ -n "$_auto_deb" ]]; then
            ok "Encontrado .deb: ${_auto_deb}"
            ask_yn _use_found "¿Usar este .deb?" "s"
            if [[ "$_use_found" == "s" ]]; then
                CFG_SUNSHINE_DEB="$_auto_deb"
            else
                ask_value CFG_SUNSHINE_DEB "Ruta completa al .deb (Enter = descargar luego)" ""
                [[ -z "$CFG_SUNSHINE_DEB" ]] && CFG_SUNSHINE_DEB="download"
            fi
        else
            warn "No se encontró .deb de Sunshine."
            printf '%s\n' "  ${DIM}Descárgalo desde: https://github.com/LizardByte/Sunshine/releases${RESET}" > "$tty"
            pick CFG_SUNSHINE_DEB "¿Qué hacer?" \
                "skip — omitir instalación del paquete (ya lo instalé)" \
                "path — indicar ruta al .deb ahora"
            if [[ "$CFG_SUNSHINE_DEB" == path* ]]; then
                ask_value CFG_SUNSHINE_DEB "Ruta completa al .deb" ""
                [[ ! -f "$CFG_SUNSHINE_DEB" ]] && warn "Archivo no encontrado — se omitirá la instalación del paquete."
            else
                CFG_SUNSHINE_DEB="skip"
            fi
        fi

        # Display
        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Sunshine — configuración de pantalla virtual ──────${RESET}" > "$tty"
        ask_value CFG_DISPLAY_NUM "Número de DISPLAY X11" ":0"
        ask_value CFG_VT_NUM      "Virtual Terminal (VT)" "vt1"
        ask_value CFG_RESOLUTION  "Resolución headless (e.g. 1920x1080)" "1366x768"

        # GPU / encoder
        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Sunshine — aceleración de hardware ───────────────${RESET}" > "$tty"

        local _vainfo_out
        _vainfo_out=$(vainfo 2>&1 || true)
        if echo "$_vainfo_out" | grep -qi "iHD"; then
            ok "Driver VAAPI detectado: iHD (Intel Media Driver)"
            CFG_GPU_DRIVER="iHD"
            CFG_ENCODER="vaapi"
        elif echo "$_vainfo_out" | grep -qi "i965"; then
            ok "Driver VAAPI detectado: i965 (Intel legacy)"
            CFG_GPU_DRIVER="i965"
            CFG_ENCODER="vaapi"
        elif echo "$_vainfo_out" | grep -qi "radeonsi\|amdgpu"; then
            ok "Driver VAAPI detectado: AMD"
            CFG_GPU_DRIVER="radeonsi"
            CFG_ENCODER="vaapi"
        elif command -v nvidia-smi &>/dev/null; then
            ok "GPU NVIDIA detectada"
            CFG_GPU_DRIVER="nvidia"
            CFG_ENCODER="nvenc"
        else
            warn "No se detectó GPU con VAAPI/NVENC — se usará encoder por software."
            CFG_GPU_DRIVER="auto"
            CFG_ENCODER="software"
        fi

        ask_yn _confirm_enc "Encoder detectado: ${BOLD}${CFG_ENCODER}${RESET} / driver: ${BOLD}${CFG_GPU_DRIVER}${RESET}. ¿Usar esto?" "s"
        if [[ "$_confirm_enc" == "n" ]]; then
            pick CFG_ENCODER "Encoder a usar:" \
                "vaapi    — Intel/AMD hardware (recomendado para headless)" \
                "nvenc    — NVIDIA hardware" \
                "software — CPU (alto uso de CPU, sin GPU)"
            CFG_ENCODER="${CFG_ENCODER%% *}"
        fi
    fi

    # ── 3. Preguntas específicas de Moonlight ──────────────────────────────────
    if [[ "$CFG_TARGET" == "moonlight" || "$CFG_TARGET" == "both" ]]; then
        printf '\n%s\n' "${BOLD}${WHITE}  ┌─ Moonlight — versión a instalar ────────────────────${RESET}" > "$tty"
        ask_value CFG_ML_VERSION "Versión de Moonlight Qt" "6.1.0"
    fi

    # ── 4. Resumen y confirmación ─────────────────────────────────────────────
    banner "Resumen — lo que se va a hacer" > "$tty"

    {
        printf '%s\n' "  ${SYM_ARROW} Componente : ${BOLD}${CFG_TARGET}${RESET}"

        if [[ "$CFG_TARGET" == "sunshine" || "$CFG_TARGET" == "both" ]]; then
            printf '%s\n' "  ${SYM_ARROW} Sunshine   : ${BOLD}${CFG_SUNSHINE_DEB}${RESET}"
            printf '%s\n' "  ${SYM_ARROW} Display    : ${BOLD}${CFG_DISPLAY_NUM}${RESET}  VT: ${BOLD}${CFG_VT_NUM}${RESET}"
            printf '%s\n' "  ${SYM_ARROW} Resolución : ${BOLD}${CFG_RESOLUTION}${RESET}"
            printf '%s\n' "  ${SYM_ARROW} Encoder    : ${BOLD}${CFG_ENCODER}${RESET}  Driver GPU: ${BOLD}${CFG_GPU_DRIVER}${RESET}"
        fi

        if [[ "$CFG_TARGET" == "moonlight" || "$CFG_TARGET" == "both" ]]; then
            printf '%s\n' "  ${SYM_ARROW} Moonlight  : ${BOLD}v${CFG_ML_VERSION}${RESET}"
        fi

        printf '%s\n' "  ${SYM_ARROW} Log        : ${BOLD}${LOG_FILE:-/var/log/streaming_setup.log}${RESET}"
        echo ""
    } > "$tty"

    ask_yn CFG_CONFIRMED "¿Proceder con la instalación?" "s"
    if [[ "$CFG_CONFIRMED" != "s" ]]; then
        printf '\n%s\n' "${YELLOW}  Cancelado por el usuario.${RESET}" > "$tty"
        exit 0
    fi

    export CFG_TARGET CFG_SUNSHINE_DEB CFG_DISPLAY_NUM CFG_VT_NUM \
           CFG_GPU_DRIVER CFG_RESOLUTION CFG_ENCODER CFG_ML_VERSION \
           CFG_CONFIRMED

    ok "Configuración confirmada — iniciando instalación..."
    echo ""
}
