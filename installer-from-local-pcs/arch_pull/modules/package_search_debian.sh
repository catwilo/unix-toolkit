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
