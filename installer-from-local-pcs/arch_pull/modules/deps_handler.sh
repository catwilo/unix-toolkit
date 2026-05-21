#!/usr/bin/env bash

handle_dependencies() {
  local deps="$1" pkg_dir="$2" sys="${3:-arch}"
  echo ""
  echo "Dependencias: $deps"
  read -p "¿Descargar dependencias? [s/N]: " REPLY
  [[ ! "$REPLY" =~ ^[sS]$ ]] && return 0
  
  IFS=',' read -ra DEP_ARRAY <<< "$deps"
  local total=${#DEP_ARRAY[@]} current=0
  echo "→ Descargando $total dependencias..."
  
  for dep in "${DEP_ARRAY[@]}"; do
    dep=$(echo "$dep" | sed 's/[<>=].*//')
    current=$((current + 1))
    echo "  [$current/$total] Buscando $dep..."
    
    local dep_info=""
    [ "$sys" = "debian" ] && dep_info=$(search_dependency_debian "$dep") || dep_info=$(search_dependency_arch "$dep")
    
    if [ -z "$dep_info" ]; then
      echo "  ✗ No encontrado: $dep"
      continue
    fi
    
    local dep_url=$(echo "$dep_info" | cut -d'|' -f1)
    local dep_file=$(echo "$dep_info" | cut -d'|' -f2)
    
    if download_file "$dep_url" "$pkg_dir/$dep_file"; then
      local size=$(du -h "$pkg_dir/$dep_file" | cut -f1)
      echo "  ✓ $dep_file ($size)"
    else
      echo "  ✗ Error: $dep"
    fi
  done
  echo "✓ Dependencias procesadas"
}

search_dependency_arch() {
  ssh_exec bash -s -- "$1" <<'DEPSEARCH'
DEP="$1"
get() { command -v curl >/dev/null 2>&1 && curl -fsSL "$@" || wget -qO- "$@"; }
jval() { grep -m1 "\"$1\"" | sed 's/.*"'"$1"'"\s*:\s*"\([^"]*\)".*/\1/'; }
J=$(get "https://archlinux.org/packages/search/json/?name=$DEP" 2>/dev/null || true)
[ -z "$J" ] && exit 1
R=$(echo "$J" | sed -n '/"results"/,/]/p' | sed -n '/{/,/}/p' | head -100)
pkg=$(echo "$R" | jval "pkgname")
ver=$(echo "$R" | jval "pkgver")
rel=$(echo "$R" | jval "pkgrel")
arch=$(echo "$R" | jval "arch")
repo=$(echo "$R" | jval "repo")
[ -n "$pkg" ] && [ -n "$ver" ] && echo "https://archlinux.org/packages/$repo/$arch/$pkg/download/|$pkg-$ver-$rel-$arch.pkg.tar.zst" && exit 0
exit 1
DEPSEARCH
}

search_dependency_debian() {
  ssh_exec bash -s -- "$1" <<'DEPSEARCH'
DEP="$1"
get() { command -v curl >/dev/null 2>&1 && curl -fsSL "$@" || wget -qO- "$@"; }
for suite in stable testing unstable; do
  page=$(get "https://packages.debian.org/$suite/$DEP" 2>/dev/null || true)
  [ -z "$page" ] && continue
  url=$(echo "$page" | grep -oP 'https?://ftp[^"]+amd64\.deb' | head -1)
  [ -n "$url" ] && echo "$url|$(basename "$url")" && exit 0
done
exit 1
DEPSEARCH
}
