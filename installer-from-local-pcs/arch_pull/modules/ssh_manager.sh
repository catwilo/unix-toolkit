#!/usr/bin/env bash

CTRL_PATH=""
SSH_CMD=()

ssh_init() {
  local target="$1" port="$2"
  CTRL_PATH="/tmp/ssh-ctrl-$$-$(date +%s)"
  SSH_CMD=(ssh -p "$port" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new 
           -o Compression=yes -o ControlMaster=auto -o ControlPath="$CTRL_PATH" -o ControlPersist=30)
  trap 'ssh_cleanup' EXIT
  
  echo "→ Conectando a $target:$port..."
  "${SSH_CMD[@]}" "$target" "echo ' ✓ Conectado'" || { echo "✗ Error conexión" >&2; return 1; }
  TARGET="$target"
}

ssh_cleanup() {
  [[ -n "$CTRL_PATH" ]] && [[ -n "${TARGET:-}" ]] && ssh -O exit -o ControlPath="$CTRL_PATH" "$TARGET" 2>/dev/null || true
}

ssh_exec() {
  "${SSH_CMD[@]}" "$TARGET" "$@"
}
