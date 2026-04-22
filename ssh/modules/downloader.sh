#!/usr/bin/env bash

download_file() {
  local url="$1"
  local dest="$2"
  
  ssh_exec "
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL '$url'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- '$url'
  else
    exit 1
  fi
  " > "$dest" 2>/dev/null
  
  if [ $? -eq 0 ] && [ -s "$dest" ]; then
    local ftype=$(file -b "$dest")
    if [[ "$ftype" =~ (Zstandard|gzip|XZ|compress) ]]; then
      return 0
    fi
  fi
  
  rm -f "$dest"
  return 1
}

verify_file() {
  local file="$1"
  [ -f "$file" ] && [[ $(file -b "$file") =~ (Zstandard|gzip|XZ|compress) ]]
}
