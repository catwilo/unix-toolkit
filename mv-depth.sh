#!/bin/bash

# Verificar parámetros
[[ $# -ne 3 ]] && { echo "Uso: $0 <ruta> <texto-antiguo> <texto-nuevo>"; exit 1; }

dir="$1"; old="$2"; new="$3"

# Función para renombrar un elemento (archivo o directorio)
rename() {
  local src="$1" dst="$2"
  mv -v "$src" "$dst" || { echo "Error al renombrar '$src'"; exit 1; }
}

# Función para mostrar los cambios propuestos
show_changes() {
  find "$dir" -depth -name "*$old*" -print0 | while IFS= read -r -d '' file; do
    # Escapar los caracteres especiales en el texto de reemplazo
    escaped_old=$(printf '%s' "$old" | sed 's/[][\.*^$(){}?+|/\\]/\\&/g')
    escaped_new=$(printf '%s' "$new" | sed 's/[&/\]/\\&/g')
    
    # Realizar el reemplazo de manera segura con sed
    new_name=$(echo "$file" | sed "s/$escaped_old/$escaped_new/g")
    
    # Solo mostrar el cambio si es realmente diferente
    if [[ "$file" != "$new_name" ]]; then
      echo -e "OLD: $file\nNEW: $new_name"
    fi
  done
}


# Mostrar cambios (archivos y directorios) y solicitar confirmación
echo "Cambios propuestos:"
show_changes

read -p "¿Confirmar renombrado de archivos y directorios? Escribe 'Yes' para continuar: " confirm
[[ "$confirm" != "Yes" ]] && exit 0

# Renombrar archivos
# Renombrar archivos
echo "Renombrando archivos..."
find "$dir" -depth -type f -name "*$old*" -print0 | while IFS= read -r -d '' file; do
  # Escapar caracteres especiales en el texto de reemplazo
  escaped_old=$(printf '%s' "$old" | sed 's/[][\.*^$(){}?+|/\\]/\\&/g')
  escaped_new=$(printf '%s' "$new" | sed 's/[&/\]/\\&/g')
  
  # Reemplazar de forma segura
  new_file=$(echo "$file" | sed "s/$escaped_old/$escaped_new/g")
  
  # Solo renombrar si el nombre cambió
  if [[ "$file" != "$new_file" ]]; then
    rename "$file" "$new_file"
  fi
done

# Renombrar directorios
# Renombrar directorios
echo "Renombrando directorios..."
find "$dir" -depth -type d -name "*$old*" -print0 | while IFS= read -r -d '' file; do
  # Escapar caracteres especiales en el texto de reemplazo
  escaped_old=$(printf '%s' "$old" | sed 's/[][\.*^$(){}?+|/\\]/\\&/g')
  escaped_new=$(printf '%s' "$new" | sed 's/[&/\]/\\&/g')
  
  # Reemplazar de forma segura
  new_file=$(echo "$file" | sed "s/$escaped_old/$escaped_new/g")
  
  # Solo renombrar si el nombre cambió
  if [[ "$file" != "$new_file" ]]; then
    rename "$file" "$new_file"
  fi
done

echo "Renombrado completado."

