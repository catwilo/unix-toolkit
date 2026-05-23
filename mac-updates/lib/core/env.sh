#!/usr/bin/env bash
# env.sh — variables globales. Solo editar esta sección para adaptar al sistema.

export MAC_UPDATES_VERSION="6.1.0"
export MAC_UPDATES_ROOT="${MAC_UPDATES_ROOT:-$HOME/.mac-updates}"

# ── Identidad VM ──────────────────────────────────────────────────────────────
export DEBIAN_USER="w"
export SSH_PORT="2222"

# ── Discos ────────────────────────────────────────────────────────────────────
export VM_DISK="$HOME/deb_working.qcow2"
export VM_BASE="$HOME/debu.qcow2"

# ── Runtime ───────────────────────────────────────────────────────────────────
export VM_PIDFILE="$MAC_UPDATES_ROOT/vm/qemu.pid"
export VM_MONITOR="$MAC_UPDATES_ROOT/vm/qemu.mon"
export LOG_OUT="$MAC_UPDATES_ROOT/logs/vm.out.log"
export LOG_ERR="$MAC_UPDATES_ROOT/logs/vm.err.log"

# ── launchd ───────────────────────────────────────────────────────────────────
export PLIST_LABEL="com.mac-updates.vm"
export PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

# ── Healthcheck ───────────────────────────────────────────────────────────────
export HC_TIMEOUT=8
export HC_SSH_TRIES=3
