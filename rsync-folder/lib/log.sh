#!/usr/bin/env bash
# lib/log.sh — unified logging + UI primitives for rsync-folder
# Source this; do not execute directly.
# Safe to source multiple times.

if [[ -z "${_RF_LOG_LOADED:-}" ]]; then
  readonly _C_RESET='\033[0m'
  readonly _C_BOLD='\033[1m'
  readonly _C_OK='\033[1;32m'
  readonly _C_WARN='\033[1;33m'
  readonly _C_ERR='\033[1;31m'
  readonly _C_INFO='\033[1;34m'
  readonly _C_CYAN='\033[1;36m'
  readonly _C_DIM='\033[2m'
  readonly _C_WHITE='\033[0;37m'
  readonly _RF_LOG_LOADED=1
fi

_log_ts() { date '+%H:%M:%S'; }

log_ok()   { printf "${_C_DIM}[%s]${_C_RESET} ${_C_OK}✔${_C_RESET}  %s\n"   "$(_log_ts)" "$*"; }
log_info() { printf "${_C_DIM}[%s]${_C_RESET} ${_C_INFO}›${_C_RESET}  %s\n" "$(_log_ts)" "$*"; }
log_warn() { printf "${_C_DIM}[%s]${_C_RESET} ${_C_WARN}⚠${_C_RESET}  %s\n" "$(_log_ts)" "$*"; }
log_err()  { printf "${_C_DIM}[%s]${_C_RESET} ${_C_ERR}✖${_C_RESET}  %s\n"  "$(_log_ts)" "$*" >&2; }
log_step() { printf "${_C_DIM}[%s]${_C_RESET} ${_C_CYAN}◆${_C_RESET}  %s\n" "$(_log_ts)" "$*"; }

log_sep() {
  local label="${1:-}"
  if [[ -n "$label" ]]; then
    printf "${_C_DIM}────── %s ──────${_C_RESET}\n" "$label"
  else
    printf "${_C_DIM}──────────────────────────${_C_RESET}\n"
  fi
}

log_kv() {
  printf "  ${_C_DIM}%-20s${_C_RESET} ${_C_WHITE}%s${_C_RESET}\n" "$1" "$2"
}

ask_yn() {
  local prompt="$1" answer
  printf "${_C_WARN}?${_C_RESET}  %s [s/N] " "$prompt"
  read -r answer </dev/tty
  [[ "$answer" =~ ^[sS]$ ]]
}
