#!/usr/bin/env bash
set -euo pipefail

VERSION="3.6.0"

LOCK_FILE="${HOME}/.sftp-share.lock"

RUN_DIR="${HOME}/.local/run"
PID_FILE="${RUN_DIR}/sftp-share-sshd.pid"

LOG_DIR="${HOME}/.local/state"
LOG_FILE="${LOG_DIR}/sftp-share.log"

PORT=""
SHARE_DIR=""
USER_NAME="$(id -un)"
PLATFORM=""
SELECTED_IP=""

FLAG_STOP=0
FLAG_STATUS=0
FLAG_RESTART=0
FLAG_FORCE=0
NO_COLOR=0

mkdir -p "$LOG_DIR" "$RUN_DIR"

# ── color ─────────────────────────────────────────────────────────────────────

for _arg in "$@"; do
  case "$_arg" in
    --no-color) NO_COLOR=1 ;;
  esac
done
unset _arg

if [[ -t 1 && "$NO_COLOR" -eq 0 ]]; then
  R=$'\033[1;31m'
  G=$'\033[1;32m'
  Y=$'\033[1;33m'
  B=$'\033[1;34m'
  Z=$'\033[0m'
else
  R=""; G=""; Y=""; B=""; Z=""
fi

# ── logging ───────────────────────────────────────────────────────────────────

log()  { echo "$(date '+%F %T') $*" >> "$LOG_FILE"; }
ok()   { echo "${G}[OK]${Z} $*";   log "OK: $*"; }
warn() { echo "${Y}[WARN]${Z} $*"; log "WARN: $*"; }
info() { echo "${B}[INFO]${Z} $*"; }
fail() { echo "${R}[FAIL]${Z} $*" >&2; log "FAIL: $*"; exit 1; }

# ── usage ─────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
sftp-share $VERSION
Usage: $(basename "$0") [OPTIONS]

Options:
  -d DIR       share directory
  -p PORT      port
  -R           restart
  -RF          force restart (kill + start)
  --stop       stop sshd
  --status     show status
  --no-color   disable color
  -h, --help   show help
EOF
  exit 0
}

# ── lock (atomic via noclobber) ───────────────────────────────────────────────

_acquire_lock() {
  # set -C makes > fail if the file already exists (atomic check+create)
  if ( set -C; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
    return 0
  fi

  # file exists — check if owner is still alive
  local oldpid
  oldpid="$(cat "$LOCK_FILE" 2>/dev/null || true)"

  if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
    fail "already running (pid=$oldpid)"
  fi

  # stale lock — remove and retry once
  rm -f "$LOCK_FILE"
  ( set -C; echo "$$" > "$LOCK_FILE" ) 2>/dev/null \
    || fail "could not acquire lock"
}

trap 'rm -f "$LOCK_FILE"' EXIT INT TERM

_acquire_lock

# ── platform ──────────────────────────────────────────────────────────────────

detect_platform() {
  if [[ -d /data/data/com.termux/files ]]; then
    PLATFORM="termux"
    PORT="${PORT:-8022}"
    SHARE_DIR="${SHARE_DIR:-${HOME}/downloads}"

  elif command -v apt-get >/dev/null 2>&1; then
    PLATFORM="debian"
    PORT="${PORT:-22}"
    SHARE_DIR="${SHARE_DIR:-${HOME}/shared}"

  elif command -v pacman >/dev/null 2>&1; then
    PLATFORM="arch"
    PORT="${PORT:-22}"
    SHARE_DIR="${SHARE_DIR:-${HOME}/shared}"

  else
    fail "unsupported platform"
  fi
}

# ── validation ────────────────────────────────────────────────────────────────

validate_port() {
  [[ "$PORT" =~ ^[0-9]+$ ]] \
    || fail "invalid port: '$PORT'"
  (( PORT >= 1 && PORT <= 65535 )) \
    || fail "port out of range: $PORT"
}

ensure_dir() {
  mkdir -p -- "$SHARE_DIR" \
    || fail "cannot create directory: $SHARE_DIR"

  SHARE_DIR="$(cd "$SHARE_DIR" && pwd -P)" \
    || fail "cannot resolve directory: $SHARE_DIR"

  touch "$SHARE_DIR/.write_test" 2>/dev/null \
    || fail "no write permission on $SHARE_DIR"

  rm -f "$SHARE_DIR/.write_test"
}

# ── dependencies ──────────────────────────────────────────────────────────────
# timeout is not available in Termux by default (needs coreutils pkg)

check_deps() {
  local base_deps=(sshd ss ip ps)
  local extra_deps=()

  [[ "$PLATFORM" != "termux" ]] && extra_deps+=(timeout sudo)

  local missing=()
  for cmd in "${base_deps[@]}" "${extra_deps[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  [[ "${#missing[@]}" -eq 0 ]] \
    || fail "missing dependencies: ${missing[*]}"
}

# ── network helpers ───────────────────────────────────────────────────────────

_get_ips() {
  ip -o -4 addr show up scope global 2>/dev/null | awk '
    $2 !~ /^(lo|docker|br-|veth|virbr|tun|wg|tap|dummy|zt|tailscale)/ {
      split($4, a, "/")
      ip = a[1]
      if (ip !~ /^(127\.|169\.254\.|10\.0\.2\.)/) {
        print ip
      }
    }
  '
}

select_ip() {
  local ips=()
  mapfile -t ips < <(_get_ips || true)

  [[ "${#ips[@]}" -gt 0 ]] \
    || fail "no usable IP found"

  if [[ "${#ips[@]}" -eq 1 ]]; then
    SELECTED_IP="${ips[0]}"
    return
  fi

  info "multiple IPs detected — select one:"
  local i=1
  for ip in "${ips[@]}"; do
    printf '  [%d] %s\n' "$i" "$ip"
    i=$(( i + 1 ))
  done

  local choice
  read -r -p "choice [1-${#ips[@]}]: " choice \
    || fail "no input received"

  [[ "$choice" =~ ^[0-9]+$ ]] \
    || fail "invalid selection"
  (( choice >= 1 && choice <= ${#ips[@]} )) \
    || fail "invalid selection"

  SELECTED_IP="${ips[$(( choice - 1 ))]}"
}

pick_first_ip() {
  local ips=()
  mapfile -t ips < <(_get_ips || true)
  [[ "${#ips[@]}" -gt 0 ]] || return 1
  SELECTED_IP="${ips[0]}"
}

# ── health checks ─────────────────────────────────────────────────────────────

_process_ok() {
  [[ -f "$PID_FILE" ]] || return 1

  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1

  local comm
  comm="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
  [[ "$comm" == "sshd" ]]
}

_port_bound() {
  ss -Htl "sport = :$PORT" 2>/dev/null | grep -q LISTEN
}

_banner_ok() {
  if [[ "$PLATFORM" == "termux" ]]; then
    # timeout may be unavailable; use bash /dev/tcp directly
    bash -c "echo >/dev/tcp/127.0.0.1/$PORT" 2>/dev/null
  else
    timeout 2 bash -c \
      "echo >/dev/tcp/127.0.0.1/$PORT" 2>/dev/null
  fi
}

# _sftp_ok: use sshd -T (effective merged config, handles Include directives).
# Falls back to grepping known config files if sshd -T is unavailable.
_sftp_ok() {
  local effective
  effective="$(sshd -T 2>/dev/null | grep -i '^subsystem ' || true)"

  if [[ -n "$effective" ]]; then
    echo "$effective" | grep -qi 'sftp'
    return
  fi

  # fallback: grep config files directly (misses Include'd fragments on
  # older setups, but better than nothing)
  grep -qiE '^[[:space:]]*Subsystem[[:space:]]+sftp' \
    /etc/ssh/sshd_config \
    /etc/ssh/sshd_config.d/*.conf \
    /data/data/com.termux/files/usr/etc/ssh/sshd_config \
    2>/dev/null
}

ssh_truth() {
  _process_ok \
    && _port_bound \
    && _banner_ok \
    && _sftp_ok
}

_ssh_ready_basic() {
  _process_ok \
    && _port_bound \
    && _banner_ok
}

# ── privilege helper ──────────────────────────────────────────────────────────

_as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return
  fi
  command -v sudo >/dev/null 2>&1 \
    || fail "sudo not found"
  sudo "$@"
}

# ── sshd control ──────────────────────────────────────────────────────────────

_sshd_start() {
  if [[ "$PLATFORM" == "termux" ]]; then
    sshd -p "$PORT" -o "PidFile=$PID_FILE"
    return
  fi

  _as_root systemctl start ssh 2>/dev/null \
    || _as_root systemctl start sshd 2>/dev/null \
    || fail "systemctl start failed"
}

_sshd_stop() {
  if [[ "$PLATFORM" == "termux" ]]; then
    if [[ -f "$PID_FILE" ]]; then
      local pid
      pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
      fi
      rm -f "$PID_FILE"
    fi
    return
  fi

  _as_root systemctl stop ssh 2>/dev/null \
    || _as_root systemctl stop sshd 2>/dev/null \
    || true
}

# ── wait helpers ──────────────────────────────────────────────────────────────
# sleep 0.2 is not portable on Termux busybox; _msleep falls back to sleep 1

_msleep() {
  sleep 0.2 2>/dev/null || sleep 1
}

_wait_until_up() {
  local secs="${1:-5}"
  local i=0
  local limit=$(( secs * 5 ))

  while [[ $i -lt $limit ]]; do
    _ssh_ready_basic && return 0
    _msleep
    i=$(( i + 1 ))
  done

  return 1
}

_wait_until_down() {
  local secs="${1:-5}"
  local i=0
  local limit=$(( secs * 5 ))

  while [[ $i -lt $limit ]]; do
    ! _process_ok && ! _port_bound && return 0
    _msleep
    i=$(( i + 1 ))
  done

  return 1
}

# ── actions ───────────────────────────────────────────────────────────────────

do_start() {
  if ssh_truth; then
    warn "already running"
    return 0
  fi

  _sshd_start

  _wait_until_up 5 \
    || fail "sshd not ready after timeout"

  _sftp_ok \
    || fail "sftp subsystem not configured in sshd"

  ok "started"
}

do_stop() {
  if ! _process_ok; then
    warn "already stopped"
    return 0
  fi

  _sshd_stop

  _wait_until_down 5 \
    || fail "sshd stop timeout"

  ok "stopped"
}

do_restart() {
  if [[ "$FLAG_FORCE" -eq 1 ]]; then
    _sshd_stop
    _wait_until_down 5 \
      || fail "force-stop timeout"
  else
    do_stop
  fi

  do_start
}

do_status() {
  # SELECTED_IP already set by main block before calling do_status
  echo "version:  $VERSION"
  echo "platform: $PLATFORM"
  echo "port:     $PORT"
  echo "dir:      $SHARE_DIR"
  echo "ip:       ${SELECTED_IP:-(unavailable)}"
  echo "user:     $USER_NAME"

  if ssh_truth; then
    ok "sshd fully functional"
    return
  fi

  warn "sshd not ready"

  _process_ok  || info "  process: DOWN"
  _port_bound  || info "  port $PORT: not bound"
  _banner_ok   || info "  banner: no response"
  _sftp_ok     || info "  sftp subsystem: not configured"
}

# ── argument parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d)
      [[ $# -ge 2 ]] || fail "missing value for -d"
      SHARE_DIR="$2"
      shift 2
      ;;
    -p)
      [[ $# -ge 2 ]] || fail "missing value for -p"
      PORT="$2"
      shift 2
      ;;
    --stop)
      FLAG_STOP=1
      shift
      ;;
    --status)
      FLAG_STATUS=1
      shift
      ;;
    -R)
      FLAG_RESTART=1
      shift
      ;;
    -RF)
      FLAG_RESTART=1   # fix: -RF implies -R
      FLAG_FORCE=1
      shift
      ;;
    --no-color)
      NO_COLOR=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

# ── init ──────────────────────────────────────────────────────────────────────

detect_platform
validate_port
check_deps

if [[ "$FLAG_STOP" -eq 0 && "$FLAG_STATUS" -eq 0 ]]; then
  ensure_dir
  select_ip
fi

# resolve IP once for status; do_status reads SELECTED_IP directly
if [[ "$FLAG_STATUS" -eq 1 ]]; then
  pick_first_ip || SELECTED_IP="(unavailable)"
fi

log "platform=$PLATFORM port=$PORT dir=${SHARE_DIR:-n/a} ip=${SELECTED_IP:-n/a} user=$USER_NAME flags=stop=$FLAG_STOP,status=$FLAG_STATUS,restart=$FLAG_RESTART,force=$FLAG_FORCE"

# ── dispatch ──────────────────────────────────────────────────────────────────

if [[ "$FLAG_STATUS" -eq 1 ]]; then
  do_status
  exit 0
fi

if [[ "$FLAG_STOP" -eq 1 ]]; then
  do_stop
  exit 0
fi

if [[ "$FLAG_RESTART" -eq 1 || "$FLAG_FORCE" -eq 1 ]]; then
  do_restart
else
  do_start
fi

echo
echo "  sftp -P $PORT ${USER_NAME}@${SELECTED_IP}"
echo "  dir: $SHARE_DIR"
echo

