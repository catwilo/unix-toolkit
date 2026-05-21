#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/scripts/arch_pull"
MODULE_DIR="$INSTALL_DIR/modules"

mkdir -p "$MODULE_DIR"

cat > "$INSTALL_DIR/init.sh" <<'EOF'
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
EOF

cat > "$MODULE_DIR/ssh_manager.sh" <<'EOF'
#!/usr/bin/env bash

CTRL_PATH=""
SSH_CMD=()

ssh_init() {
  local target="$1" port="$2"
  CTRL_PATH="/tmp/ssh-ctrl-$$-$(date +%s)"
  SSH_CMD=(ssh -p "$port" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new 
           -o Compression=yes -o ControlMaster=auto -o ControlPath="$CTRL_PATH" -o ControlPersist=30)
  trap 'ssh_cleanup' EXIT
  
  echo "→ Conectando a $target:$port..."
  "${SSH_CMD[@]}" "$target" "echo ' ✓ Conectado'" || { echo "✗ Error conexión" >&2; return 1; }
  TARGET="$target"
}

ssh_cleanup() {
  [[ -n "$CTRL_PATH" ]] && [[ -n "${TARGET:-}" ]] && ssh -O exit -o ControlPath="$CTRL_PATH" "$TARGET" 2>/dev/null || true
}

ssh_exec() {
  "${SSH_CMD[@]}" "$TARGET" "$@"
}
EOF

cat > "$MODULE_DIR/package_search.sh" <<'EOF'
#!/usr/bin/env bash

search_package_arch() {
  ssh_exec bash -s -- "$1" <<'SEARCH'
set -e
APP="$1"
get() { command -v curl >/dev/null 2>&1 && curl -fsSL "$@" || wget -qO- "$@"; }
jval() { grep -m1 "\"$1\"" | sed 's/.*"'"$1"'"\s*:\s*"\([^"]*\)".*/\1/'; }

extract_info() {
  local json="$1"
  local result=$(echo "$json" | sed -n '/"results"/,/^\s*\]/p' | sed -n '/^\s*{/,/^\s*}/p' | head -100)
  local pkg=$(echo "$result" | jval "pkgname")
  local ver=$(echo "$result" | jval "pkgver")
  local rel=$(echo "$result" | jval "pkgrel")
  local arch=$(echo "$result" | jval "arch")
  local repo=$(echo "$result" | jval "repo")
  
  if [ -n "$pkg" ] && [ -n "$ver" ] && [ -n "$rel" ] && [ -n "$arch" ]; then
    local fullname="${pkg}-${ver}-${rel}-${arch}"
    local version_str="${ver}-${rel}-${arch}"
    local deps=$(echo "$result" | grep -o '"depends"[^]]*\]' | grep -o '"[^"]*"' | grep -v "depends" | tr -d '"' | tr '\n' ',' | sed 's/,$//')
    echo "https://archlinux.org/packages/$repo/$arch/$pkg/download/|${fullname}.pkg.tar.zst|$deps|$version_str"
    return 0
  fi
  return 1
}

echo " • Repositorios Arch..." >&2
J=$(get "https://archlinux.org/packages/search/json/?name=$APP" 2>/dev/null || true)
[ -n "$J" ] && echo "$J" | grep -q '"results".*\[.*\]' && extract_info "$J" && exit 0

J=$(get "https://archlinux.org/packages/search/json/?q=$APP" 2>/dev/null || true)
[ -n "$J" ] && echo "$J" | grep -q '"results".*\[.*\]' && extract_info "$J" && exit 0

echo " • AUR..." >&2
if get -I "https://aur.archlinux.org/cgit/aur.git/snapshot/$APP.tar.gz" 2>/dev/null | grep -q "200 OK"; then
  echo "https://aur.archlinux.org/cgit/aur.git/snapshot/$APP.tar.gz|$APP.tar.gz||snapshot-$(date +%Y%m%d)"
  exit 0
fi

echo " • GitHub..." >&2
R=$(get "https://api.github.com/search/repositories?q=$APP" 2>/dev/null | grep -m1 '"full_name"' | cut -d\" -f4 || true)
if [ -n "$R" ]; then
  REL=$(get "https://api.github.com/repos/$R/releases/latest" 2>/dev/null || true)
  TAG=$(echo "$REL" | grep -m1 '"tag_name"' | cut -d\" -f4 || echo "latest")
  URL=$(echo "$REL" | grep -Eo 'https://[^"]+\.(pkg\.tar\.zst|tar\.gz|tar\.xz)' | head -1 || true)
  [ -n "$URL" ] && echo "$URL|$(basename "$URL")||$TAG" && exit 0
fi
exit 1
SEARCH
}
EOF

cat > "$MODULE_DIR/package_search_debian.sh" <<'EOF'
#!/usr/bin/env bash

search_package_debian() {
  ssh_exec bash -s -- "$1" <<'SEARCH'
set -e
APP="$1"
get() { command -v curl >/dev/null 2>&1 && curl -fsSL "$@" || wget -qO- "$@"; }

search_deb() {
  local suite="$1"
  echo " • Debian $suite..." >&2
  local page=$(get "https://packages.debian.org/$suite/$APP" 2>/dev/null || true)
  [ -z "$page" ] && return 1
  local url=$(echo "$page" | grep -oP 'https?://ftp[^"]+amd64\.deb' | head -1)
  [ -z "$url" ] && return 1
  local ver=$(echo "$page" | grep -oP '(?<=<span id="version">)[^<]+' | head -1 || echo "latest")
  echo "$url|$(basename "$url")||$ver-$suite-amd64"
  return 0
}

search_deb "stable" && exit 0
search_deb "testing" && exit 0
search_deb "unstable" && exit 0

echo " • GitHub..." >&2
R=$(get "https://api.github.com/search/repositories?q=$APP" 2>/dev/null | grep -m1 '"full_name"' | cut -d\" -f4 || true)
if [ -n "$R" ]; then
  REL=$(get "https://api.github.com/repos/$R/releases/latest" 2>/dev/null || true)
  TAG=$(echo "$REL" | grep -m1 '"tag_name"' | cut -d\" -f4 || echo "latest")
  URL=$(echo "$REL" | grep -Eo 'https://[^"]+\.deb' | head -1 || echo "$REL" | grep -Eo 'https://[^"]+\.(tar\.gz|tar\.xz)' | head -1 || true)
  [ -n "$URL" ] && echo "$URL|$(basename "$URL")||github-$TAG" && exit 0
fi
exit 1
SEARCH
}
EOF

cat > "$MODULE_DIR/downloader.sh" <<'EOF'
#!/usr/bin/env bash

download_file() {
  local url="$1" dest="$2"
  ssh_exec "command -v curl >/dev/null 2>&1 && curl -fsSL '$url' || wget -qO- '$url'" > "$dest" 2>/dev/null
  if [ $? -eq 0 ] && [ -s "$dest" ]; then
    local ftype=$(file -b "$dest")
    [[ "$ftype" =~ (Zstandard|gzip|XZ|compress|Debian) ]] && return 0
  fi
  rm -f "$dest"
  return 1
}
EOF

cat > "$MODULE_DIR/deps_handler.sh" <<'EOF'
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
EOF

cat > "$INSTALL_DIR/arch_pull.sh" <<'EOF'
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
EOF

chmod +x "$INSTALL_DIR/init.sh"
chmod +x "$INSTALL_DIR/arch_pull.sh"
chmod +x "$MODULE_DIR"/*.sh

echo "✓ Instalación completa en: $INSTALL_DIR"
echo ""
echo "Uso: $INSTALL_DIR/arch_pull.sh usuario@host paquete"
echo ""
echo "Alias recomendado (agregar a ~/.bashrc):"
echo "  alias getpkg='$INSTALL_DIR/arch_pull.sh'"
