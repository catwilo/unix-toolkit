#!/usr/bin/env bash
# 01-qemu-nix.sh — asegura QEMU >= 7.0 disponible via Nix.
set -euo pipefail

source "$(dirname "$0")/../lib/ui/output.sh"

_MIN_VER="7.0"

_qemu_ok() {
  command -v qemu-system-x86_64 >/dev/null 2>&1 || return 1
  local ver maj min
  ver=$(qemu-system-x86_64 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
  IFS='.' read -r maj min <<< "$ver"
  local rmin rmaj
  IFS='.' read -r rmaj rmin <<< "$_MIN_VER"
  (( maj > rmaj || ( maj == rmaj && min >= rmin ) ))
}

if _qemu_ok; then
  print_success "QEMU disponible ($(qemu-system-x86_64 --version | head -1)) — sin cambios"
  exit 0
fi

if command -v qemu-system-x86_64 >/dev/null 2>&1; then
  print_warning "QEMU encontrado pero por debajo de v${_MIN_VER} — actualizando via Nix..."
else
  print_info "QEMU no encontrado — instalando via Nix..."
fi

nix profile add nixpkgs#qemu
export PATH="$HOME/.nix-profile/bin:$PATH"

_qemu_ok || {
  print_error "Instalación de QEMU falló o sigue por debajo de v${_MIN_VER}"
  exit 1
}

print_success "QEMU listo ($(qemu-system-x86_64 --version | head -1))"
