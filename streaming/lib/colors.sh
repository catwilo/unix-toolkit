#!/usr/bin/env bash
# =============================================================================
# lib/colors.sh — Colores, logging, banners y selector interactivo robusto
# =============================================================================

# ── Paleta ────────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
BLUE=$'\033[0;34m'
WHITE=$'\033[1;37m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ── Símbolos ──────────────────────────────────────────────────────────────────
SYM_OK="✔"
SYM_WARN="⚠"
SYM_ERR="✖"
SYM_INFO="●"
SYM_ARROW="▶"

# ── Log helpers ───────────────────────────────────────────────────────────────
# Elimina secuencias de escape ANSI/OSC de forma robusta (CSI ...m, OSC ...BEL/ST).
_strip_ansi() {
    printf '%s\n' "$1" | sed -E $'s/\033\\][^\007]*(\007|\033\\\\)//g; s/\033\\[[0-9;?]*[a-zA-Z]//g'
}

_log_tee() {
    local line="$1"
    printf '%s\n' "$line"
    if [[ -n "${LOG_FILE:-}" ]]; then
        _strip_ansi "$line" >> "$LOG_FILE"
    fi
}

log()  { _log_tee "${CYAN}${SYM_INFO}${RESET}  ${DIM}$(date '+%H:%M:%S')${RESET}  $*"; }
ok()   { _log_tee "${GREEN}${SYM_OK}${RESET}   ${DIM}$(date '+%H:%M:%S')${RESET}  $*"; }
warn() { _log_tee "${YELLOW}${SYM_WARN}${RESET}  ${DIM}$(date '+%H:%M:%S')${RESET}  $*"; }
fail() { _log_tee "${RED}${SYM_ERR}${RESET}  ${DIM}$(date '+%H:%M:%S')${RESET}  $*" >&2; exit 1; }

step() {
    local n="$1" total="$2"; shift 2
    printf '\n%s\n' "${BOLD}${BLUE}[${n}/${total}]${RESET}${BOLD} $*${RESET}"
}

# ── Ancho útil del terminal/pane (acotado) ─────────────────────────────────────
# Devuelve el ancho actual menos 2, con mínimo 24 y máximo 56, para que las
# cajas y divisores nunca se partan en panes estrechos de byobu.
_term_width() {
    local cols="${COLUMNS:-0}"
    [[ "$cols" -le 0 ]] && cols=$(tput cols 2>/dev/null || echo 56)
    cols=$((cols - 2))
    (( cols < 24 )) && cols=24
    (( cols > 56 )) && cols=56
    printf '%s' "$cols"
}

# ── Banner ────────────────────────────────────────────────────────────────────
# Caja ligera adaptada al ancho real. No se parte en panes angostos.
banner() {
    local title="${1:-}" sub="${2:-}"
    local width line
    width=$(_term_width)
    printf -v line '%*s' "$width" ''; line="${line// /─}"
    printf '\n%s\n' "${BOLD}${BLUE}┌${line}┐${RESET}"
    printf '%s\n'   "${BOLD}${BLUE}│${RESET}$(printf " %-$((width-1))s" "$title")${BOLD}${BLUE}│${RESET}"
    [[ -n "$sub" ]] && \
        printf '%s\n' "${BOLD}${BLUE}│${RESET}${DIM}$(printf " %-$((width-1))s" "$sub")${RESET}${BOLD}${BLUE}│${RESET}"
    printf '%s\n\n' "${BOLD}${BLUE}└${line}┘${RESET}"
}

# ── Divisor ───────────────────────────────────────────────────────────────────
divider() {
    local width line
    width=$(_term_width)
    printf -v line '%*s' "$width" ''; line="${line// /─}"
    printf '%s\n' "${DIM}${line}${RESET}"
}

# =============================================================================
# _get_tty — devuelve el fd de tty disponible para I/O interactivo
# =============================================================================
_get_tty() {
    if [[ -c /dev/tty ]] && ( exec </dev/tty ) 2>/dev/null; then
        echo "/dev/tty"
    elif [[ -t 0 ]]; then
        echo "/dev/stdin"
    else
        echo ""
    fi
}

# =============================================================================
# pick VAR "Pregunta" "Op1" "Op2" ...
# =============================================================================
pick() {
    local _var="$1" _prompt="$2"; shift 2
    local _opts=("$@")
    local _i _key _choice

    local _tty
    _tty=$(_get_tty)

    if [[ -z "$_tty" ]]; then
        fail "No hay terminal interactivo disponible.\n  Pasa el argumento directamente: $0 sunshine|moonlight|both"
    fi

    {
        printf '\n%s\n' "${BOLD}${CYAN}  ${_prompt}${RESET}"
        for _i in "${!_opts[@]}"; do
            printf '  %s  %s\n' "${BOLD}${MAGENTA}[$((_i+1))]${RESET}" "${_opts[$_i]}"
        done
        printf '\n'
    } > "$_tty"

    while true; do
        printf '  %s ' "${BOLD}${WHITE}${SYM_ARROW} Opción [1-${#_opts[@]}]:${RESET}" > "$_tty"
        if ! IFS= read -r _key < "$_tty"; then
            fail "No se pudo leer la selección (EOF en ${_tty})."
        fi
        if [[ "$_key" =~ ^[0-9]+$ ]] && (( _key >= 1 && _key <= ${#_opts[@]} )); then
            _choice="${_opts[$((_key-1))]}"
            printf -v "$_var" '%s' "$_choice"
            ok "Seleccionado: ${BOLD}${_choice}${RESET}"
            return 0
        fi
        printf '%s\n' "${YELLOW}${SYM_WARN}  Opción inválida — ingresa un número entre 1 y ${#_opts[@]}${RESET}" > "$_tty"
    done
}

# =============================================================================
# ask_yn VAR "Pregunta" [default: s|n]
# =============================================================================
ask_yn() {
    local _var="$1" _prompt="$2" _default="${3:-s}"
    local _hint _ans _tty

    _tty=$(_get_tty)
    [[ -z "$_tty" ]] && fail "No hay terminal interactivo disponible."

    if [[ "$_default" == "s" ]]; then
        _hint="${BOLD}[S/n]${RESET}"
    else
        _hint="${BOLD}[s/N]${RESET}"
    fi

    while true; do
        printf '  %s  %s %s ' "${CYAN}${SYM_INFO}${RESET}" "${_prompt}" "$_hint" > "$_tty"
        IFS= read -r _ans < "$_tty"
        _ans="${_ans,,}"
        [[ -z "$_ans" ]] && _ans="$_default"
        case "$_ans" in
            s|si|sí|y|yes) printf -v "$_var" 's'; return 0 ;;
            n|no)          printf -v "$_var" 'n'; return 0 ;;
            *) printf '%s\n' "${YELLOW}${SYM_WARN}  Responde 's' o 'n'.${RESET}" > "$_tty" ;;
        esac
    done
}

# =============================================================================
# ask_value VAR "Prompt" "default"
# =============================================================================
ask_value() {
    local _var="$1" _prompt="$2" _default="${3:-}"
    local _ans _tty

    _tty=$(_get_tty)
    [[ -z "$_tty" ]] && fail "No hay terminal interactivo disponible."

    local _hint=""
    [[ -n "$_default" ]] && _hint=" ${DIM}[Enter = ${_default}]${RESET}"

    printf '  %s  %s%s: ' "${CYAN}${SYM_INFO}${RESET}" "${_prompt}" "$_hint" > "$_tty"
    IFS= read -r _ans < "$_tty"
    [[ -z "$_ans" ]] && _ans="$_default"
    printf -v "$_var" '%s' "$_ans"
}
