#!/usr/bin/env bash
# SETUP_VERIFICATION.sh — Pre-setup environment checks for spfx-tool.
# Verifica que el host tenga lo necesario ANTES de correr setup.sh.
# No requiere interacción. No modifica nada.
# shellcheck shell=bash
# set -e is intentionally omitted: this script accumulates all failures before
# exiting so the user sees every problem at once, not just the first one.
set -uo pipefail

_PASS=0
_FAIL=0
_WARN=0

_green='\033[0;32m'
_red='\033[0;31m'
_yellow='\033[0;33m'
_reset='\033[0m'

_ok()   { echo -e "  ${_green}✔${_reset}  $*"; _PASS=$((_PASS+1)); }
_fail() { echo -e "  ${_red}✗${_reset}  $*"; _FAIL=$((_FAIL+1)); }
_warn() { echo -e "  ${_yellow}⚠${_reset}  $*"; _WARN=$((_WARN+1)); }

echo ""
echo "spfx-tool — verificación pre-setup"
echo "===================================="
echo ""

# ── OS ────────────────────────────────────────────────────────────────────────
echo "[ OS ]"
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" == "debian" && "${VERSION_CODENAME:-}" == "trixie" ]]; then
        _ok "Debian 13 (trixie) detectado"
    elif [[ "${ID:-}" == "debian" ]]; then
        _warn "Debian detectado pero no es trixie (VERSION_CODENAME=${VERSION_CODENAME:-desconocido}) — puede funcionar pero no está soportado"
    else
        _fail "OS no soportado: ${PRETTY_NAME:-desconocido} — se requiere Debian 13 (trixie)"
    fi
else
    _fail "/etc/os-release no encontrado — no se puede verificar OS"
fi

_arch="$(uname -m)"
if [[ "${_arch}" == "x86_64" ]]; then
    _ok "Arquitectura x86_64"
else
    _fail "Arquitectura no soportada: ${_arch} — se requiere x86_64"
fi
echo ""

# ── Usuario ───────────────────────────────────────────────────────────────────
echo "[ Usuario ]"
if [[ "$(id -u)" -eq 0 ]]; then
    _fail "Corriendo como root — spfx-tool usa Podman rootless, debe correrse como usuario normal"
else
    _ok "Usuario no-root: $(id -un)"
fi

# Subuid/subgid para rootless Podman
if grep -q "^$(id -un):" /etc/subuid 2>/dev/null || grep -q "^$(id -u):" /etc/subuid 2>/dev/null; then
    _ok "subuid configurado para $(id -un)"
else
    _fail "subuid no configurado para $(id -un) — rootless Podman lo requiere. Correr: sudo usermod --add-subuids 100000-165535 $(id -un)"
fi

if grep -q "^$(id -un):" /etc/subgid 2>/dev/null || grep -q "^$(id -u):" /etc/subgid 2>/dev/null; then
    _ok "subgid configurado para $(id -un)"
else
    _fail "subgid no configurado para $(id -un) — correr: sudo usermod --add-subgids 100000-165535 $(id -un)"
fi
echo ""

# ── Podman ────────────────────────────────────────────────────────────────────
echo "[ Podman ]"
if command -v podman &>/dev/null; then
    _podman_ver="$(podman --version 2>/dev/null | awk '{print $3}')"
    _ok "podman ${_podman_ver} encontrado en PATH"

    # Rootless smoke test
    if podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -q "true"; then
        _ok "Podman rootless OK"
    else
        _warn "No se pudo confirmar modo rootless de Podman — verificar con: podman info | grep -i rootless"
    fi

    # Storage configurado
    if podman info &>/dev/null; then
        _ok "Podman storage accesible"
    else
        _fail "Podman storage inaccesible — correr: podman system migrate"
    fi
else
    _fail "podman no encontrado en PATH — instalar: apt-get install podman"
fi
echo ""

# ── Bash ──────────────────────────────────────────────────────────────────────
echo "[ Bash ]"
_bash_ver="${BASH_VERSION:-desconocido}"
_bash_major="${BASH_VERSION%%.*}"
if [[ "${_bash_major:-0}" -ge 4 ]]; then
    _ok "Bash ${_bash_ver}"
else
    _fail "Bash 4+ requerido — versión detectada: ${_bash_ver}"
fi
echo ""

# ── Espacio en disco ──────────────────────────────────────────────────────────
echo "[ Disco ]"
_home_avail_kb="$(df -k "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
_home_avail_gb=$(( ${_home_avail_kb:-0} / 1024 / 1024 ))
if [[ "${_home_avail_gb}" -ge 5 ]]; then
    _ok "${_home_avail_gb} GB libres en \$HOME — suficiente (mínimo ~5 GB para imagen + proyectos)"
elif [[ "${_home_avail_gb}" -ge 2 ]]; then
    _warn "${_home_avail_gb} GB libres en \$HOME — puede ser ajustado para imagen + proyectos"
else
    _fail "${_home_avail_gb} GB libres en \$HOME — insuficiente. La imagen Podman requiere ~2 GB"
fi
echo ""

# ── Herramientas opcionales (CI) ──────────────────────────────────────────────
echo "[ Herramientas opcionales (CI) ]"
if command -v shellcheck &>/dev/null; then
    _ok "shellcheck $(shellcheck --version 2>/dev/null | awk '/^version/{print $2}')"
else
    _warn "shellcheck no encontrado — requerido para ci/run.sh (lint). Instalar: apt-get install shellcheck"
fi

if command -v shfmt &>/dev/null; then
    _ok "shfmt $(shfmt --version 2>/dev/null)"
else
    _warn "shfmt no encontrado — requerido para ci/run.sh (format check). Ver: https://github.com/mvdan/sh/releases"
fi
echo ""

# ── Resumen ───────────────────────────────────────────────────────────────────
echo "===================================="
echo -e "  ${_green}✔ ${_PASS} OK${_reset}   ${_yellow}⚠ ${_WARN} advertencias${_reset}   ${_red}✗ ${_FAIL} errores${_reset}"
echo ""

if [[ "${_FAIL}" -gt 0 ]]; then
    echo -e "  ${_red}Corregir los errores antes de correr setup.sh${_reset}"
    echo ""
    exit 1
elif [[ "${_WARN}" -gt 0 ]]; then
    echo -e "  ${_yellow}Advertencias encontradas — el setup puede continuar pero revisar los items marcados${_reset}"
    echo ""
    exit 0
else
    echo -e "  ${_green}Entorno listo. Correr: bash spfx-tool/setup.sh${_reset}"
    echo ""
    exit 0
fi
