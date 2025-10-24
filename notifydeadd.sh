#!/bin/bash
if [[ $# -eq 0 ]]; then
  echo "Uso: $(basename "$0") [-i icono.svg] 'Título' 'Mensaje'"
  exit 1
fi

ico=""
if [[ "$1" == "-i" && -n "$2" ]]; then
  ico="$HOME/icos/$2"
  shift 2
fi

if [[ -n "$ico" && ! -f "$ico" ]]; then
  echo "Error: icono no encontrado en $ico"
  exit 1
fi

notify-send "$@" ${ico:+ "<img src=\"$ico\"/>"}

