#!/usr/bin/env bash
# lib/core.sh — Runtime primitives: logging, env validation, helpers.
# Source this file; never execute directly.
# shellcheck shell=bash

if [[ "${_SPFX_CORE_LOADED:-}" == "1" ]]; then return 0; fi
_SPFX_CORE_LOADED=1

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# ── Logging ───────────────────────────────────────────────────────────────────
_log() {
    local level="$1"; shift
    printf '[%s] %s %s\n' "$level" "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" \
        >> "${LOG_FILE:-/dev/null}"
}
log_ok()    { _log INFO  "$*"; echo -e "${GREEN}  ✔${NC}  $*"; }
log_info()  { _log INFO  "$*"; echo -e "${CYAN}  →${NC}  $*"; }
log_warn()  { _log WARN  "$*"; echo -e "${YELLOW}  ⚠${NC}  $*" >&2; }
log_err()   { _log ERROR "$*"; echo -e "${RED}  ✘${NC}  $*" >&2; }
log_die()   { log_err "$*"; exit 1; }
log_step()  { _log STEP  "$*"
              echo -e "\n${BOLD}${CYAN}══ $* ${NC}${DIM}$(printf '═%.0s' {1..40})${NC}"; }
log_debug() { [[ "${SPFX_DEBUG:-0}" == "1" ]] || return 0
              _log DEBUG "$*"; echo -e "${DIM}  ⋯  $*${NC}"; }

# ── Environment ───────────────────────────────────────────────────────────────
# Debian 13 (trixie) on x86_64.
export SPFX_ENV="debian"

# ── Version loader ────────────────────────────────────────────────────────────
spfx_load_versions() {
    local venv="${SPFX_DIR}/versions.env"
    [[ -f "$venv" ]] || log_die "versions.env not found: $venv"
    # shellcheck source=/dev/null
    source "$venv"
    log_debug "Versions: SPFx=${SPFX_GENERATOR_VERSION} Node=${NODE_VERSION}"
}

# ── Precondition gates ────────────────────────────────────────────────────────
require_debian() {
    [[ "$(id -u)" -ne 0 ]] || log_die "Do not run as root — Podman requires rootless mode"
}

require_podman() {
    require_debian
    command -v podman >/dev/null 2>&1 \
        || log_die "Podman not installed. Run: spfx-bootstrap"
    podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -q true \
        || log_die "Podman is not in rootless mode. See: https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md"
}

require_project() {
    local name="${1:-}"
    validate_project_name "$name"
    [[ -d "${SPFX_DIR}/projects/${name}" ]] \
        || log_die "Project not found: ${SPFX_DIR}/projects/${name}"
}

# ── Validation ────────────────────────────────────────────────────────────────
validate_project_name() {
    local n="${1:-}"
    [[ -n "$n" ]] \
        || log_die "Project name is required"
    [[ "$n" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] \
        || log_die "Invalid project name: '$n' (letter first, then alphanumeric/dash/underscore)"
    [[ "${#n}" -le 64 ]] \
        || log_die "Project name too long (max 64 chars)"
}

validate_node_spfx_compat() {
    spfx_load_versions
    local node_major="${NODE_VERSION%%.*}"
    if (( node_major < SPFX_MIN_NODE || node_major > SPFX_MAX_NODE )); then
        log_die "Node ${NODE_VERSION} incompatible with SPFx ${SPFX_GENERATOR_VERSION} (need ${SPFX_MIN_NODE}–${SPFX_MAX_NODE})"
    fi
}

# ── Network ───────────────────────────────────────────────────────────────────
get_local_ip() {
    local ip
    ip="$(ip route get 1.1.1.1 2>/dev/null \
        | awk '/src/{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')" || true
    if [[ -z "$ip" ]]; then
        ip="$(ip addr show 2>/dev/null \
            | awk '/inet / && !/127\.0\.0\.1/{split($2,a,"/");print a[1];exit}')" || true
    fi
    echo "${ip:-127.0.0.1}"
}

# ── Temp files ────────────────────────────────────────────────────────────────
make_tmpfile() {
    local prefix="${1:-spfx}" ext="${2:-.sh}"
    mktemp "${TMPDIR:-/tmp}/${prefix}-XXXXXX${ext}"
}

_SPFX_TMPFILES=()
register_tmpfile() { _SPFX_TMPFILES+=("$1"); }
cleanup_tmpfiles() {
    local f
    for f in "${_SPFX_TMPFILES[@]:-}"; do if [[ -f "$f" ]]; then rm -f "$f"; fi; done
}
trap cleanup_tmpfiles EXIT

# ── Log rotation ──────────────────────────────────────────────────────────────
# Keeps the SPFX_DIR/logs/ directory bounded. Called from bootstrap (and any
# long-lived entry point) after the new log file has been created — never deletes
# the current $LOG_FILE.
#   prune_logs [keep]   keep = number of newest files to retain (default 50)
prune_logs() {
    local keep="${1:-50}"
    local logs_dir="${SPFX_DIR}/logs"
    [[ -d "$logs_dir" ]] || return 0
    # Newest first; skip first $keep; delete the rest. Never the active LOG_FILE.
    local current="${LOG_FILE:-}"
    local f
    while IFS= read -r f; do
        if [[ "$f" == "$current" ]]; then continue; fi
        rm -f "$f"
    done < <(find "$logs_dir" -maxdepth 1 -type f -name '*.log' -printf '%T@ %p\n' \
             | sort -rn | awk -v k="$keep" 'NR>k {print $2}')
}
