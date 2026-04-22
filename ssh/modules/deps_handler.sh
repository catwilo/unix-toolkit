#!/usr/bin/env bash

handle_dependencies() {
  local deps="$1"
  local pkg_dir="$2"
  
  echo ""
  echo "Dependencias encontradas: $deps"
  read -p "¿Descargar dependencias? [s/N]: " REPLY
  
  [[ ! "$REPLY" =~ ^[sS]$ ]] && return 0
  
  IFS=',' read -ra DEP_ARRAY <<< "$deps"
  local total=${#DEP_ARRAY[@]}
  local current=0
  
  echo "→ Descargando $total dependencias..."
  
  for dep in "${DEP_ARRAY[@]}"; do
    dep=$(echo "$dep" | sed 's/[<>=].*//')
    current=$((current + 1))
    
    echo "  [$current/$total] Buscando $dep..."
    
    local dep_info=$(search_dependency "$dep")
    
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
      echo "  ✗ Error descargando: $dep"
    fi
  done
  
  echo ""
  echo "✓ Dependencias procesadas"
}

search_dependency() {
  local dep="$1"
  
  ssh_exec bash -s -- "$dep" <<'DEPSEARCH'
set -e
DEP="$1"

get() { 
  command -v curl >/dev/null 2>&1 && curl -fsSL "$@" || wget -qO- "$@"
}

jval() {
  grep -m1 "\"$1\"" | sed 's/.*"'"$1"'"\s*:\s*"\([^"]*\)".*/\1/'
}

J=$(get "https://archlinux.org/packages/search/json/?name=$DEP" 2>/dev/null || true)

if [ -n "$J" ] && echo "$J" | grep -q '"results".*\[.*\]'; then
  RESULT=$(echo "$J" | sed -n '/"results"/,/^\s*\]/p' | sed -n '/^\s*{/,/^\s*}/p' | head -100)
  
  pkg=$(echo "$RESULT" | jval "pkgname")
  ver=$(echo "$RESULT" | jval "pkgver")
  rel=$(echo "$RESULT" | jval "pkgrel")
  arch=$(echo "$RESULT" | jval "arch")
  repo=$(echo "$RESULT" | jval "repo")
  
  if [ -n "$pkg" ] && [ -n "$ver" ] && [ -n "$rel" ] && [ -n "$arch" ]; then
    fullname="${pkg}-${ver}-${rel}-${arch}"
    echo "https://archlinux.org/packages/$repo/$arch/$pkg/download/|${fullname}.pkg.tar.zst"
    exit 0
  fi
fi

exit 1
DEPSEARCH
}
