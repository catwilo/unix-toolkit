#!/usr/bin/env bash
set -euo pipefail

D="$HOME/scripts/neko/groups"
G="${1:-}"
shift
[[ -z "$G" ]] && echo "uso: rmneko <grupo> <apps...>" && exit 1
F="$D/$G"
[[ ! -f "$F" ]] && echo "grupo no existe: $G" && exit 1

mapfile -t rm < <(grep -vE '^\s*(#|$)' <<< "$*")
[[ ${#rm[@]} -eq 0 ]] && echo "sin apps para remover" && exit 1

# Lee el archivo actual
mapfile -t cur < "$F"

# Reconstrucción filtrada usando awk con -v array
printf '%s\n' "${cur[@]}" | awk -v rem_list="$(printf '%s|' "${rm[@]}")" '
  BEGIN{split(rem_list,R,"|")}
  !seen[$0]++ {
    skip=0
    for(i in R) if($0==R[i]) skip=1
    if(!skip) print
  }' > "$F"

echo "apps removidas del grupo $G: ${rm[*]}"
