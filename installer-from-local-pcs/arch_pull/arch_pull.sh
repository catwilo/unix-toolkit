#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$SCRIPT_DIR/modules"

source "$MODULE_DIR/ssh_manager.sh"
source "$MODULE_DIR/package_search.sh"
source "$MODULE_DIR/package_search_debian.sh"
source "$MODULE_DIR/downloader.sh"
source "$MODULE_DIR/deps_handler.sh"

PORT=8022

show_usage() { echo "Uso: $0 user@host paquete [-p puerto]" >&2; exit 1; }

while getopts p: opt; do 
  case "$opt" in p) PORT=$OPTARG;; *) show_usage;; esac
done
shift $((OPTIND-1))

[[ $# -lt 2 ]] && show_usage

TARGET="$1"
APP="$2"

LOCAL_SYSTEM="arch"
[ -f /etc/debian_version ] && LOCAL_SYSTEM="debian"
echo "→ Sistema: $LOCAL_SYSTEM"

ssh_init "$TARGET" "$PORT"

echo "→ Buscando '$APP'..."
if [ "$LOCAL_SYSTEM" = "debian" ]; then
  RESULT=$(search_package_debian "$APP")
else
  RESULT=$(search_package_arch "$APP")
fi

DL_URL=$(echo "$RESULT" | cut -d'|' -f1)
FILENAME=$(echo "$RESULT" | cut -d'|' -f2)
DEPS=$(echo "$RESULT" | cut -d'|' -f3)
VERSION=$(echo "$RESULT" | cut -d'|' -f4)

[[ -z "$DL_URL" ]] && { echo "✗ No encontrado" >&2; exit 1; }

echo " ✓ Encontrado: $FILENAME"
echo " ✓ Versión: $VERSION"

ssh_cleanup
echo ""
echo "→ Preparando directorio..."

INIT_RESULT=$("$SCRIPT_DIR/init.sh" "$APP" "$VERSION") || exit 1

SYSTEM=$(echo "$INIT_RESULT" | tail -1 | cut -d'|' -f1)
PKG_DIR=$(echo "$INIT_RESULT" | tail -1 | cut -d'|' -f2)

echo ""
echo "→ Descargando..."

ssh_init "$TARGET" "$PORT"

if download_file "$DL_URL" "$PKG_DIR/$FILENAME"; then
  SIZE=$(du -h "$PKG_DIR/$FILENAME" | cut -f1)
  echo "✓ Descargado: $FILENAME ($SIZE)"
else
  echo "✗ Error en descarga" >&2
  exit 1
fi

[ -n "$DEPS" ] && handle_dependencies "$DEPS" "$PKG_DIR" "$LOCAL_SYSTEM"

ssh_cleanup

echo ""
echo "✓ Guardado en: $PKG_DIR/"
echo ""
echo "Para instalar:"
if [ "$LOCAL_SYSTEM" = "arch" ]; then
  echo "  sudo pacman -U $PKG_DIR/*.pkg.tar.zst"
else
  echo "  sudo dpkg -i $PKG_DIR/*.deb"
  echo "  sudo apt-get install -f"
fi
