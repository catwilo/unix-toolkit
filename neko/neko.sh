#!/usr/bin/env bash
set -euo pipefail

d="$HOME/scripts/neko/groups"
g="${1:-}"
cmd="${2:-}"

[[ -z "$g" ]] && ls "$d" && exit

f="$d/$g"
[[ ! -f "$f" ]] && echo "grupo no existe: $g" && exit 1

if [[ "$cmd" == "ls" ]]; then
  cat "$f" && exit 0
fi

mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$f")
[[ ${#pkgs[@]} -eq 0 ]] && echo "sin paquetes en grupo" && exit 1

# Intento de instalación y captura de error
err=$(mktemp)
if ! sudo pacman -S --noconfirm --needed "${pkgs[@]}" 2>"$err"; then
  # Busca líneas sobre conflicto
  if grep -qE 'conflicting|exists in filesystem' "$err"; then
    grep -E 'error: .*conflicting|exists in filesystem' "$err" \
      | head -n1 \
      | sed -E 's/.*: (.+) .*/\1/'
    echo "→ paquete en conflicto"
  else
    echo "Error desconocido durante pacman"
    cat "$err"
  fi
  rm "$err"
  echo "Intentando con apt Termux..."
  apt install -y "${pkgs[@]}"
fi
