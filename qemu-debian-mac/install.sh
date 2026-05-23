#!/bin/bash
# Shebang /bin/bash intencional — funciona con bash 3.2 de macOS antes del re-exec.

# ── Bootstrap: garantizar bash 4+ ────────────────────────────────────────────
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for _p in \
    "$HOME/.nix-profile/bin/bash" \
    "/nix/var/nix/profiles/default/bin/bash"; do
    [[ -x "$_p" ]] && exec "$_p" "$0" "$@"
  done
  command -v nix >/dev/null 2>&1 || {
    printf '[ERR] Nix no encontrado. Instala en: https://nixos.org/download\n' >&2
    exit 1
  }
  nix profile add nixpkgs#bash
  for _p in "$HOME/.nix-profile/bin/bash" "/nix/var/nix/profiles/default/bin/bash"; do
    [[ -x "$_p" ]] && exec "$_p" "$0" "$@"
  done
  printf '[ERR] Instalación de bash via Nix falló\n' >&2; exit 1
fi

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT_DIR/lib/core/env.sh"
source "$ROOT_DIR/lib/ui/output.sh"
source "$ROOT_DIR/lib/core/checks.sh"

# ── Lock: evitar dos instalaciones paralelas ──────────────────────────────────
LOCK_DIR="/tmp/mac-updates-install.lock"
mkdir "$LOCK_DIR" 2>/dev/null || {
  print_error "Otra instalación en curso — si es stale: rm -rf ${LOCK_DIR}"
  exit 1
}
trap 'rm -rf "$LOCK_DIR"' EXIT

print_header "mac-updates v${MAC_UPDATES_VERSION} installer"

# ── Preflight ─────────────────────────────────────────────────────────────────
run_all_checks

# ── Dependencias ──────────────────────────────────────────────────────────────
print_header "Dependencias"

if ! command -v tmux >/dev/null 2>&1; then
  print_info "tmux no encontrado — instalando via Nix..."
  nix profile add nixpkgs#tmux
  command -v tmux >/dev/null 2>&1 || {
    print_error "Instalación de tmux falló"
    exit 1
  }
fi
print_success "tmux $(tmux -V)"

if ! command -v socat >/dev/null 2>&1; then
  print_info "socat no encontrado — instalando via Nix..."
  nix profile add nixpkgs#socat 2>/dev/null \
    || print_warning "socat no disponible — stop usará SIGTERM como fallback"
else
  print_success "socat disponible"
fi

# ── Detección de instalación previa ───────────────────────────────────────────
print_header "Estado previo"

# VM corriendo
if bash "$ROOT_DIR/healthchecks/vm-health.sh" 2>/dev/null; then
  print_warning "VM activa y respondiendo SSH."
  printf "  Detenerla para continuar? [y/N] "; read -r _r
  [[ "$_r" =~ ^[Yy]$ ]] || { print_info "Instalación cancelada."; exit 0; }
  "$ROOT_DIR/bin/mac-updates" stop 2>/dev/null || true
  sleep 2
fi

# Sesión tmux huérfana
if tmux has-session -t "mac-vm" 2>/dev/null; then
  print_warning "Sesión tmux 'mac-vm' existente — eliminando..."
  tmux kill-session -t "mac-vm" 2>/dev/null || true
fi

# Disco
_USE_EXISTING=0
if [[ -f "$VM_DISK" ]]; then
  _SIZE=$(qemu-img info "$VM_DISK" 2>/dev/null \
    | grep 'virtual size' | awk '{print $3, $4}' || echo "?")
  print_warning "Disco existente: ${VM_DISK} (${_SIZE})"
  printf "  [k] Mantener y usar  [r] Reemplazar con overlay limpio  > "; read -r _r
  [[ "${_r,,}" == "r" ]] && _USE_EXISTING=0 || _USE_EXISTING=1
fi

# Disco personalizado
print_header "Disco activo"
printf "  Configurado: %s\n" "$VM_DISK"
printf "  Usar esta ruta? [Y] o ingresa otra: "; read -r _custom
if [[ -n "$_custom" && "$_custom" != "Y" && "$_custom" != "y" ]]; then
  [[ -f "$_custom" ]] || { print_error "No encontrado: ${_custom}"; exit 1; }
  VM_DISK="$_custom"
fi
print_info "Disco: ${VM_DISK}"

# ── Instalación ───────────────────────────────────────────────────────────────
print_header "Instalando"

mkdir -p "$MAC_UPDATES_ROOT/vm" "$MAC_UPDATES_ROOT/logs"
echo "minimal" > "$MAC_UPDATES_ROOT/vm/current-profile"

chmod +x "$ROOT_DIR/bin/mac-updates"
chmod +x "$ROOT_DIR/installers/"*.sh
chmod +x "$ROOT_DIR/healthchecks/"*.sh
chmod +x "$ROOT_DIR/scripts/"*.sh

bash "$ROOT_DIR/installers/01-qemu-nix.sh"

if [[ $_USE_EXISTING -eq 1 ]]; then
  print_success "Disco reutilizado: ${VM_DISK}"
else
  [[ -f "$VM_BASE" ]] || {
    print_error "Disco base no encontrado: ${VM_BASE}"
    print_error "Edita VM_BASE en lib/core/env.sh"
    exit 1
  }
  if [[ -f "$VM_DISK" ]]; then
    mv "$VM_DISK" "${VM_DISK}.bak.$(date +%Y%m%d%H%M%S)"
    print_info "Disco anterior renombrado como .bak"
  fi
  qemu-img create -f qcow2 -b "$VM_BASE" -F qcow2 "$VM_DISK"
  print_success "Disco creado: ${VM_DISK}"
fi

# launchd — siempre reinstala para apuntar al binario actual
bash "$ROOT_DIR/installers/04-launchd.sh"

# PATH en .zshrc
_BIN_DIR="${ROOT_DIR}/bin"
_PATH_MARKER="# mac-updates: PATH"
if [[ "${SHELL}" == */zsh ]] || [[ -f "$HOME/.zshrc" ]]; then
  _RC="$HOME/.zshrc"
else
  _RC="$HOME/.bashrc"
fi

if grep -q "$_PATH_MARKER" "$_RC" 2>/dev/null; then
  python3 - "$_RC" "$_PATH_MARKER" "$_BIN_DIR" << 'PYEOF'
import sys
path, marker, bin_dir = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).readlines()
out, i = [], 0
while i < len(lines):
    if lines[i].rstrip('\n') == marker:
        out.append(lines[i])
        i += 1
        if i < len(lines):
            out.append(f'export PATH="{bin_dir}:$PATH"\n')
            i += 1
    else:
        out.append(lines[i])
        i += 1
open(path, 'w').writelines(out)
PYEOF
else
  printf '\n%s\nexport PATH="%s:$PATH"\n' "$_PATH_MARKER" "$_BIN_DIR" >> "$_RC"
fi
print_success "PATH → ${_BIN_DIR}"

# ── Verificación ──────────────────────────────────────────────────────────────
_LAUNCHD_OK=0
launchctl list 2>/dev/null | grep -q "${PLIST_LABEL}" && _LAUNCHD_OK=1

# ── Resumen final ─────────────────────────────────────────────────────────────
echo ""
print_header "mac-updates v${MAC_UPDATES_VERSION} — listo"
echo ""
printf "  %-24s %s\n"    "Binario"            "${ROOT_DIR}/bin/mac-updates"
printf "  %-24s %s\n"    "Disco"              "${VM_DISK}"
printf "  %-24s %s\n"    "SSH"                "ssh ${DEBIAN_USER}@localhost -p ${SSH_PORT}"
printf "  %-24s %s\n"    "Profile default"    "minimal (1 CPU / 512M)"
printf "  %-24s "        "sshl"
printf "${_GREEN}[OK]${_RESET} instalado en %s\n" "${_RC##*/}"
printf "  %-24s "        "Reboot persistente"
if [[ $_LAUNCHD_OK -eq 1 ]]; then
  printf "${_GREEN}[OK]${_RESET} launchd activo — VM arranca automáticamente\n"
else
  printf "${_YELLOW}[WARN]${_RESET} launchd registrado, verifica con: launchctl list | grep mac-updates\n"
fi
echo ""
printf "  Recarga tu shell:  ${_YELLOW}source %s${_RESET}\n" "~/${_RC##*/}"
echo ""
echo "  Comandos"
echo "  ──────────────────────────────────────────────────"
printf "  %-30s %s\n" "mac-updates start"         "iniciar VM"
printf "  %-30s %s\n" "mac-updates gui"            "iniciar con ventana X11/i3"
printf "  %-30s %s\n" "mac-updates stop"           "apagar VM"
printf "  %-30s %s\n" "mac-updates status"         "estado completo"
printf "  %-30s %s\n" "mac-updates boost on|off"   "más recursos / volver a minimal"
printf "  %-30s %s\n" "mac-updates -h"             "ayuda completa"
echo ""

# ── Preguntar si arrancar ahora ───────────────────────────────────────────────
printf "  Iniciar la VM ahora? [Y/n] "; read -r _start
if [[ ! "${_start,,}" =~ ^n ]]; then
  echo ""
  source "${_RC}" 2>/dev/null || true
  "$ROOT_DIR/bin/mac-updates" start
fi
