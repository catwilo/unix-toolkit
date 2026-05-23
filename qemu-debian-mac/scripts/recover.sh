#!/usr/bin/env bash
# recover.sh — mata QEMU si existe, reinicia via mac-updates start con backoff.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/lib/ui/output.sh"
source "$ROOT_DIR/lib/core/env.sh"

MAX_ATTEMPTS=5
BACKOFF_BASE=3

print_header "Recovery"

# Fast path: ya está sana
if bash "$ROOT_DIR/healthchecks/vm-health.sh" 2>/dev/null; then
  print_success "VM sana — nada que hacer"
  exit 0
fi

# Matar instancia anterior si existe
if [[ -f "$VM_PIDFILE" ]]; then
  _OLD=$(cat "$VM_PIDFILE")
  if kill -0 "$_OLD" 2>/dev/null; then
    print_info "Deteniendo QEMU (PID ${_OLD})..."
    kill -TERM "$_OLD" 2>/dev/null || true
    local _w=0
    while kill -0 "$_OLD" 2>/dev/null && (( _w < 8 )); do sleep 1; (( _w++ )); done
    kill -KILL "$_OLD" 2>/dev/null || true
  fi
  rm -f "$VM_PIDFILE"
fi

# Limpiar sesión tmux huérfana
tmux kill-session -t "mac-vm" 2>/dev/null || true

# Reiniciar
print_info "Iniciando VM..."
"$ROOT_DIR/bin/mac-updates" start

# Polling con backoff exponencial
_delay=$BACKOFF_BASE
for _attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  print_info "Verificando... (intento ${_attempt}/${MAX_ATTEMPTS}, esperando ${_delay}s)"
  sleep "$_delay"
  if bash "$ROOT_DIR/healthchecks/vm-health.sh" 2>/dev/null; then
    print_success "Recovery OK (intento ${_attempt})"
    exit 0
  fi
  _delay=$(( _delay * 2 > 30 ? 30 : _delay * 2 ))
done

print_error "Recovery falló tras ${MAX_ATTEMPTS} intentos"
print_error "Revisa logs: mac-updates logs err"
exit 1
