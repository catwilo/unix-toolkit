#!/usr/bin/env bash
set -euo pipefail

g="${1:-}"
shift || true
apps=("$@")
dir="$HOME/scripts/neko/groups"
f="$dir/$g"

[[ -z "$g" ]] && echo "grupo requerido" && exit 1
mkdir -p "$dir"

if [[ ! -f "$f" ]]; then
  printf '%s\n' "${apps[@]}" > "$f"
  echo "grupo creado: $g"
  exit 0
fi

# leer existentes
mapfile -t exist < "$f"
all=("${exist[@]}" "${apps[@]}")
printf '%s\n' "${all[@]}" | awk '!seen[$0]++' > "$f"

echo "grupo actualizado: $g"
