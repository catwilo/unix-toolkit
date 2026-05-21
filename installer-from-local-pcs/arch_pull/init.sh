#!/usr/bin/env bash
set -euo pipefail

detect_system() {
  [ -f /etc/debian_version ] && echo "debian" && return
  [ -f /etc/arch-release ] && echo "arch" && return
  echo "unknown"
}

prepare_version_directory() {
  local app="$1" version="$2" base="$HOME/gitApps"
  local app_base="$base/$app" version_dir="$app_base/$version"
  
  [ ! -d "$base" ] && echo "→ Creando $base" && mkdir -p "$base"
  [ ! -d "$app_base" ] && mkdir -p "$app_base"
  
  if [ -d "$version_dir" ]; then
    echo "⚠ La versión $version ya existe" >&2
    read -p "¿Sobrescribir? [s/N]: " REPLY
    [[ ! "$REPLY" =~ ^[sS]$ ]] && echo "Cancelado" >&2 && return 1
    rm -rf "$version_dir"
  fi
  
  mkdir -p "$version_dir"
  echo "$version_dir"
}

main() {
  local app="${1:-}" version="${2:-}"
  [ -z "$app" ] && echo "Error: especificar app" >&2 && return 1
  [ -z "$version" ] && echo "Error: especificar versión" >&2 && return 1
  
  echo "→ Detectando sistema..."
  local system=$(detect_system)
  
  case "$system" in
    debian) echo " ✓ Sistema: Debian/Ubuntu";;
    arch) echo " ✓ Sistema: Arch Linux";;
    *) echo "✗ Sistema no soportado" >&2 && return 1;;
  esac
  
  local version_dir=$(prepare_version_directory "$app" "$version")
  [ $? -ne 0 ] && return 1
  
  echo " ✓ Directorio: $version_dir"
  echo "$system|$version_dir"
}

main "$@"
