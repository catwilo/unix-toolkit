#!/usr/bin/env bash
set -euo pipefail                                           # fallar en errores, variables indefinidas y pipes rotos
D="$HOME/scripts/neko/groups"; G="${1:-}"; CMD="${2:-}"     # rutas y argumentos
[[ -z "$G" ]] && ls "$D" && exit 0                          # sin grupo: listar grupos y salir
F="$D/$G"; [[ ! -f "$F" ]] && echo "grupo no existe: $G" && exit 1  # grupo no existe
[[ "$CMD" == "ls" ]] && cat "$F" && exit 0                 # mostrar contenido del grupo
mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$F")              # leer paquetes ignorando vacíos y comentarios
[[ ${#pkgs[@]} -eq 0 ]] && echo "grupo vacío: $G" && exit 1 # sin paquetes
yay -S --needed --noconfirm "${pkgs[@]}" || { echo "⚠️ yay falló durante instalación"; exit 1; }  # instalar
yay -Yc &>/dev/null && echo "✅ dependencias de construcción removidas" || echo "⚠️ error limpiando dependencias huérfanas"  # limpiar
