#!/usr/bin/env bash
# arch_pull.sh - Descarga paquetes directamente al host vía túnel SSH
set -euo pipefail

PORT=8022
DEST="$PWD"

while getopts p:d: opt; do case "$opt" in p)PORT=$OPTARG;;d)DEST=$OPTARG;;esac;done
shift $((OPTIND-1))

[[ $# -lt 2 ]] && { echo "Uso: $0 user@host paquete [-p puerto] [-d destino]" >&2; exit 1; }
TARGET="$1" APP="$2"

CTRL_PATH="/tmp/ssh-ctrl-$$"
SSH=(ssh -p "$PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o Compression=yes -o ControlMaster=auto -o ControlPath="$CTRL_PATH" -o ControlPersist=30)

trap "ssh -O exit -o ControlPath='$CTRL_PATH' '$TARGET' 2>/dev/null || true" EXIT

echo "→ Conectando a $TARGET:$PORT..."
"${SSH[@]}" "$TARGET" "echo ' ✓ Conectado'" || { echo "✗ Error de conexión" >&2; exit 1; }

echo "→ Buscando '$APP'..."
RESULT=$("${SSH[@]}" "$TARGET" bash -s -- "$APP" <<'REMOTE'
set -e
APP="$1"
get() { 
  if command -v curl >/dev/null 2>&1; then 
    curl -fsSL "$@"
  else 
    wget -qO- "$@"
  fi
}

jval() {
  grep -m1 "\"$1\"" | sed 's/.*"'"$1"'"\s*:\s*"\([^"]*\)".*/\1/'
}

echo " • Repositorios Arch..." >&2
J=$(get "https://archlinux.org/packages/search/json/?name=$APP" 2>/dev/null || true)

if [ -n "$J" ] && echo "$J" | grep -q '"results".*\[.*\]'; then
  RESULT=$(echo "$J" | sed -n '/"results"/,/^\s*\]/p' | sed -n '/^\s*{/,/^\s*}/p' | head -100)
  
  pkg=$(echo "$RESULT" | jval "pkgname")
  ver=$(echo "$RESULT" | jval "pkgver")
  rel=$(echo "$RESULT" | jval "pkgrel")
  arch=$(echo "$RESULT" | jval "arch")
  repo=$(echo "$RESULT" | jval "repo")
  
  if [ -n "$pkg" ] && [ -n "$ver" ] && [ -n "$rel" ] && [ -n "$arch" ]; then
    fullname="${pkg}-${ver}-${rel}-${arch}"
    
    # Obtener dependencias
    DEPS=$(echo "$RESULT" | grep -o '"depends"[^]]*\]' | grep -o '"[^"]*"' | grep -v "depends" | tr -d '"' | tr '\n' ',' | sed 's/,$//')
    
    echo "###https://archlinux.org/packages/$repo/$arch/$pkg/download/###${fullname}.pkg.tar.zst###$DEPS"
    exit 0
  fi
fi

J=$(get "https://archlinux.org/packages/search/json/?q=$APP" 2>/dev/null || true)

if [ -n "$J" ] && echo "$J" | grep -q '"results".*\[.*\]'; then
  RESULT=$(echo "$J" | sed -n '/"results"/,/^\s*\]/p' | sed -n '/^\s*{/,/^\s*}/p' | head -100)
  
  pkg=$(echo "$RESULT" | jval "pkgname")
  ver=$(echo "$RESULT" | jval "pkgver")
  rel=$(echo "$RESULT" | jval "pkgrel")
  arch=$(echo "$RESULT" | jval "arch")
  repo=$(echo "$RESULT" | jval "repo")
  
  if [ -n "$pkg" ] && [ -n "$ver" ] && [ -n "$rel" ] && [ -n "$arch" ]; then
    fullname="${pkg}-${ver}-${rel}-${arch}"
    
    DEPS=$(echo "$RESULT" | grep -o '"depends"[^]]*\]' | grep -o '"[^"]*"' | grep -v "depends" | tr -d '"' | tr '\n' ',' | sed 's/,$//')
    
    echo "###https://archlinux.org/packages/$repo/$arch/$pkg/download/###${fullname}.pkg.tar.zst###$DEPS"
    exit 0
  fi
fi

echo " • AUR..." >&2
if get -I "https://aur.archlinux.org/cgit/aur.git/snapshot/$APP.tar.gz" 2>/dev/null|grep -q "200 OK"; then
  echo "###https://aur.archlinux.org/cgit/aur.git/snapshot/$APP.tar.gz###$APP.tar.gz###"
  exit 0
fi

echo " • GitHub..." >&2
R=$(get "https://api.github.com/search/repositories?q=$APP" 2>/dev/null|grep -m1 '"full_name"'|cut -d\" -f4||true)
if [ -n "$R" ]; then
  A=$(get "https://api.github.com/repos/$R/releases/latest" 2>/dev/null|grep -Eo 'https://[^"]+\.(pkg\.tar\.zst|tar\.gz|tar\.xz)'|head -1||true)
  if [ -n "$A" ]; then
    echo "###$A###$(basename "$A")###"
    exit 0
  fi
fi

echo "✗ No encontrado" >&2; exit 1
REMOTE
) || { echo "✗ Búsqueda fallida" >&2; exit 1; }

DL_URL=$(grep -oP '###\K[^#]+' <<<"$RESULT" | head -1)
FILENAME=$(grep -oP '###[^#]+###\K[^#]+' <<<"$RESULT" | head -1)
DEPS=$(grep -oP '###[^#]+###[^#]+###\K.*' <<<"$RESULT")

[[ -z "$DL_URL" ]] && { echo "✗ Paquete no encontrado" >&2; exit 1; }

echo " ✓ Encontrado: $FILENAME"

download_package() {
  local url="$1"
  local name="$2"
  
  "${SSH[@]}" "$TARGET" "
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL '$url'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- '$url'
  else
    exit 1
  fi
  " > "$DEST/$name" 2>/dev/null
  
  if [ $? -eq 0 ] && [ -s "$DEST/$name" ]; then
    local ftype=$(file -b "$DEST/$name")
    if [[ "$ftype" =~ (Zstandard|gzip|XZ|compress) ]]; then
      return 0
    else
      rm -f "$DEST/$name"
      return 1
    fi
  else
    rm -f "$DEST/$name"
    return 1
  fi
}

echo "→ Descargando paquete principal..."
if download_package "$DL_URL" "$FILENAME"; then
  SIZE=$(du -h "$DEST/$FILENAME" | cut -f1)
  echo "✓ Descargado: $DEST/$FILENAME ($SIZE)"
else
  echo "✗ Descarga fallida" >&2
  exit 1
fi

if [ -n "$DEPS" ]; then
  echo ""
  echo "Dependencias encontradas: $DEPS"
  read -p "¿Descargar dependencias? [s/N]: " REPLY
  
  if [[ "$REPLY" =~ ^[sS]$ ]]; then
    IFS=',' read -ra DEP_ARRAY <<< "$DEPS"
    TOTAL=${#DEP_ARRAY[@]}
    CURRENT=0
    
    echo "→ Descargando $TOTAL dependencias..."
    
    for dep in "${DEP_ARRAY[@]}"; do
      dep=$(echo "$dep" | sed 's/[<>=].*//')
      CURRENT=$((CURRENT + 1))
      
      echo "  [$CURRENT/$TOTAL] Buscando $dep..."
      
      DEP_RESULT=$("${SSH[@]}" "$TARGET" bash -s -- "$dep" <<'DEPDL'
set -e
DEP="$1"
get() { 
  if command -v curl >/dev/null 2>&1; then 
    curl -fsSL "$@"
  else 
    wget -qO- "$@"
  fi
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
    echo "###https://archlinux.org/packages/$repo/$arch/$pkg/download/###${fullname}.pkg.tar.zst"
    exit 0
  fi
fi
exit 1
DEPDL
) || { echo "  ✗ No encontrado: $dep"; continue; }
      
      DEP_URL=$(grep -oP '###\K[^#]+' <<<"$DEP_RESULT" | head -1)
      DEP_FILE=$(grep -oP '###[^#]+###\K.*' <<<"$DEP_RESULT")
      
      if [ -n "$DEP_URL" ] && [ -n "$DEP_FILE" ]; then
        if download_package "$DEP_URL" "$DEP_FILE"; then
          DEP_SIZE=$(du -h "$DEST/$DEP_FILE" | cut -f1)
          echo "  ✓ $DEP_FILE ($DEP_SIZE)"
        else
          echo "  ✗ Error descargando: $dep"
        fi
      fi
    done
    
    echo ""
    echo "✓ Proceso completado"
  fi
fi
