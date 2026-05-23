#!/usr/bin/env bash
# secrets.sh — gestión de password via Keychain de macOS.
# El password NUNCA toca disco, historial de shell ni args de proceso.

_KEYCHAIN_SERVICE="mac-updates"
_KEYCHAIN_ACCOUNT="${DEBIAN_USER:-w}"

secrets_prompt_and_store() {
  print_info "Configurando password para usuario '${_KEYCHAIN_ACCOUNT}'"
  local pass pass2 attempt
  for attempt in 1 2 3; do
    IFS= read -r -s -p "  Password: " pass;  echo >&2
    IFS= read -r -s -p "  Confirmar: " pass2; echo >&2
    if [[ "$pass" != "$pass2" ]]; then
      print_error "Las contraseñas no coinciden (intento ${attempt}/3)"
      unset pass pass2
      [[ $attempt -lt 3 ]] && continue
      print_error "Demasiados errores — cancelado"; return 1
    fi
    if [[ ${#pass} -lt 4 ]]; then
      print_error "Mínimo 4 caracteres"
      unset pass pass2
      [[ $attempt -lt 3 ]] && continue
      return 1
    fi
    break
  done
  security unlock-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null || true
  if ! security add-generic-password \
      -s "$_KEYCHAIN_SERVICE" -a "$_KEYCHAIN_ACCOUNT" -w "$pass" -U 2>/dev/null; then
    print_error "Error al escribir en Keychain — verifica permisos de macOS"
    unset pass pass2; return 1
  fi
  unset pass pass2
  print_success "Password guardado en Keychain (servicio: ${_KEYCHAIN_SERVICE})"
}

secrets_get_password() {
  security find-generic-password \
    -s "$_KEYCHAIN_SERVICE" -a "$_KEYCHAIN_ACCOUNT" -w 2>/dev/null || {
    print_error "Password no encontrado en Keychain — ejecuta: mac-updates passwd"
    return 1
  }
}

secrets_delete() {
  security delete-generic-password \
    -s "$_KEYCHAIN_SERVICE" -a "$_KEYCHAIN_ACCOUNT" 2>/dev/null || true
  print_info "Entrada de Keychain eliminada"
}
