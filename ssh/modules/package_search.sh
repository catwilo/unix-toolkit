#!/usr/bin/env bash

search_package() {
  local app="$1"
  
  ssh_exec bash -s -- "$app" <<'SEARCH'
set -e
APP="$1"

get() { 
  command -v curl >/dev/null 2>&1 && curl -fsSL "$@" || wget -qO- "$@"
}

jval() {
  grep -m1 "\"$1\"" | sed 's/.*"'"$1"'"\s*:\s*"\([^"]*\)".*/\1/'
}

extract_package_info() {
  local json="$1"
  local result=$(echo "$json" | sed -n '/"results"/,/^\s*\]/p' | sed -n '/^\s*{/,/^\s*}/p' | head -100)
  
  local pkg=$(echo "$result" | jval "pkgname")
  local ver=$(echo "$result" | jval "pkgver")
  local rel=$(echo "$result" | jval "pkgrel")
  local arch=$(echo "$result" | jval "arch")
  local repo=$(echo "$result" | jval "repo")
  
  if [ -n "$pkg" ] && [ -n "$ver" ] && [ -n "$rel" ] && [ -n "$arch" ]; then
    local fullname="${pkg}-${ver}-${rel}-${arch}"
    local deps=$(echo "$result" | grep -o '"depends"[^]]*\]' | grep -o '"[^"]*"' | 
                 grep -v "depends" | tr -d '"' | tr '\n' ',' | sed 's/,$//')
    
    echo "https://archlinux.org/packages/$repo/$arch/$pkg/download/|${fullname}.pkg.tar.zst|$deps"
    return 0
  fi
  return 1
}

echo " • Repositorios Arch..." >&2

J=$(get "https://archlinux.org/packages/search/json/?name=$APP" 2>/dev/null || true)
[ -n "$J" ] && echo "$J" | grep -q '"results".*\[.*\]' && extract_package_info "$J" && exit 0

J=$(get "https://archlinux.org/packages/search/json/?q=$APP" 2>/dev/null || true)
[ -n "$J" ] && echo "$J" | grep -q '"results".*\[.*\]' && extract_package_info "$J" && exit 0

echo " • AUR..." >&2
if get -I "https://aur.archlinux.org/cgit/aur.git/snapshot/$APP.tar.gz" 2>/dev/null | grep -q "200 OK"; then
  echo "https://aur.archlinux.org/cgit/aur.git/snapshot/$APP.tar.gz|$APP.tar.gz|"
  exit 0
fi

echo " • GitHub..." >&2
R=$(get "https://api.github.com/search/repositories?q=$APP" 2>/dev/null | grep -m1 '"full_name"' | cut -d\" -f4 || true)
if [ -n "$R" ]; then
  A=$(get "https://api.github.com/repos/$R/releases/latest" 2>/dev/null | 
      grep -Eo 'https://[^"]+\.(pkg\.tar\.zst|tar\.gz|tar\.xz)' | head -1 || true)
  if [ -n "$A" ]; then
    echo "$A|$(basename "$A")|"
    exit 0
  fi
fi

exit 1
SEARCH
}
