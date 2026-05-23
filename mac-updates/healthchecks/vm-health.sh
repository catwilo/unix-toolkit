#!/usr/bin/env bash
# vm-health.sh — dos capas: proceso QEMU vivo + sshd respondiendo en puerto.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/lib/ui/output.sh"
source "$ROOT_DIR/lib/core/env.sh"

# ── 1. Proceso QEMU ───────────────────────────────────────────────────────────
if [[ ! -f "$VM_PIDFILE" ]]; then
  print_error "Pidfile no encontrado: ${VM_PIDFILE}"
  exit 1
fi
_PID=$(cat "$VM_PIDFILE")
kill -0 "$_PID" 2>/dev/null || {
  print_error "Proceso QEMU (PID ${_PID}) no está corriendo"
  exit 1
}

# ── 2. Puerto SSH accesible ───────────────────────────────────────────────────
_sshd_ok() {
  local i
  for i in $(seq 1 "${HC_SSH_TRIES:-3}"); do
    nc -z -w "${HC_TIMEOUT:-8}" 127.0.0.1 "${SSH_PORT}" 2>/dev/null && return 0
    [[ $i -lt ${HC_SSH_TRIES:-3} ]] && sleep 1
  done
  return 1
}

if ! _sshd_ok; then
  print_error "sshd no responde en puerto ${SSH_PORT}"
  exit 2
fi

print_success "VM healthy (PID ${_PID}, sshd en :${SSH_PORT})"
