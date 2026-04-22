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
URL=$("${SSH[@]}" "$TARGET" bash -s -- "$APP" <<'REMOTE'
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
  RESULT=$(echo "$J" | sed -n '/"results"/,/^\s*\]/p' | sed -n '/^\s*{/,/^\s*}/p' | head -50)
  
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

J=$(get "https://archlinux.org/packages/search/json/?q=$APP" 2>/dev/null || true)

if [ -n "$J" ] && echo "$J" | grep -q '"results".*\[.*\]'; then
  RESULT=$(echo "$J" | sed -n '/"results"/,/^\s*\]/p' | sed -n '/^\s*{/,/^\s*}/p' | head -50)
  
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

echo " • AUR..." >&2
if get -I "https://aur.archlinux.org/cgit/aur.git/snapshot/$APP.tar.gz" 2>/dev/null|grep -q "200 OK"; then
  echo "###https://aur.archlinux.org/cgit/aur.git/snapshot/$APP.tar.gz###$APP.tar.gz"
  exit 0
fi

echo " • GitHub..." >&2
R=$(get "https://api.github.com/search/repositories?q=$APP" 2>/dev/null|grep -m1 '"full_name"'|cut -d\" -f4||true)
if [ -n "$R" ]; then
  A=$(get "https://api.github.com/repos/$R/releases/latest" 2>/dev/null|grep -Eo 'https://[^"]+\.(pkg\.tar\.zst|tar\.gz|tar\.xz)'|head -1||true)
  if [ -n "$A" ]; then
    echo "###$A###$(basename "$A")"
    exit 0
  fi
fi

echo "✗ No encontrado" >&2; exit 1
REMOTE
) || { echo "✗ Búsqueda fallida" >&2; exit 1; }

DL_URL=$(grep -oP '###\K[^#]+' <<<"$URL" | head -1)
FILENAME=$(grep -oP '###[^#]+###\K.*' <<<"$URL")

[[ -z "$DL_URL" ]] && { echo "✗ Paquete no encontrado" >&2; exit 1; }

echo " ✓ Encontrado: $FILENAME"
echo "→ Descargando..."

# Descargar usando comando directo sin heredoc
"${SSH[@]}" "$TARGET" "
if command -v curl >/dev/null 2>&1; then
  curl -fsSL '$DL_URL'
elif command -v wget >/dev/null 2>&1; then
  wget -qO- '$DL_URL'
else
  exit 1
fi
" > "$DEST/$FILENAME" 2>/dev/null

if [ $? -eq 0 ] && [ -s "$DEST/$FILENAME" ]; then
  SIZE=$(du -h "$DEST/$FILENAME" | cut -f1)
  FILETYPE=$(file -b "$DEST/$FILENAME")
  
  if [[ "$FILETYPE" =~ (Zstandard|gzip|XZ|compress) ]]; then
    echo "✓ Descargado: $DEST/$FILENAME ($SIZE)"
  else
    echo "✗ Archivo corrupto: $FILETYPE" >&2
    rm -f "$DEST/$FILENAME"
    exit 1
  fi
else
  echo "✗ Descarga fallida" >&2
  rm -f "$DEST/$FILENAME"
  exit 1
fi
