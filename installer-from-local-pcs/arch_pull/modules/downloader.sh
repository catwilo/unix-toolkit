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
