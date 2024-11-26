#!/bin/bash

# Verificar que se hayan pasado exactamente 3 parámetros
if [ $# -ne 3 ]; then
  echo "Uso: $0 <ruta> <texto-antiguo> <texto-nuevo>"
  exit 1
fi

# Asignar los parámetros a variables
dir="$1"
old_text="$2"
new_text="$3"

# Renombrar archivos primero
find "$dir" -depth -type f -name "*$old_text*" -exec bash -c 'mv "$0" "${0//$1/$2}"' {} "$old_text" "$new_text" \;

# Renombrar directorios después
find "$dir" -depth -type d -name "*$old_text*" -exec bash -c 'mv "$0" "${0//$1/$2}"' {} "$old_text" "$new_text" \;

echo "Renombrado completado."

