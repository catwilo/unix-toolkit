#!/usr/bin/env bash
# checks.sh — guards de preflight. Se hace source en install.sh y bin/mac-updates.

run_all_checks() {
  _check_macos
  _check_x86_64
  _check_nix
  _check_port_free
}

_check_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || {
    print_error "Se requiere macOS (detectado: $(uname -s))"
    exit 1
  }
}

_check_x86_64() {
  [[ "$(uname -m)" == "x86_64" ]] || {
    print_error "Se requiere host Intel x86_64 (detectado: $(uname -m))"
    exit 1
  }
}

_check_nix() {
  command -v nix >/dev/null 2>&1 || {
    print_error "Nix no encontrado — instala en: https://nixos.org/download"
    exit 1
  }
}

_check_port_free() {
  local pids
  pids=$(lsof -i "TCP:${SSH_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)
  if [[ -n "$pids" ]]; then
    print_error "Puerto ${SSH_PORT} en uso por PID(s): ${pids}"
    print_error "Cambia SSH_PORT en lib/core/env.sh o libera el puerto"
    exit 1
  fi
}

# Guard runtime: la VM debe estar corriendo antes de ciertos comandos
require_vm_running() {
  if [[ ! -f "$VM_PIDFILE" ]]; then
    print_error "VM no iniciada — arranca con: mac-updates start"
    exit 1
  fi
  local pid
  pid=$(cat "$VM_PIDFILE")
  kill -0 "$pid" 2>/dev/null || {
    print_error "Proceso QEMU (PID ${pid}) no está corriendo"
    print_error "Recupera con: mac-updates recover"
    exit 1
  }
}
