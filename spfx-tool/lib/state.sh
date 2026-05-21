#!/usr/bin/env bash
# lib/state.sh — Persistent state management: snapshots, rollback metadata, verify cache.
# All mutable runtime state lives under $SPFX_DIR/state/, never in logs/.
# shellcheck shell=bash

if [[ "${_SPFX_STATE_LOADED:-}" == "1" ]]; then return 0; fi
_SPFX_STATE_LOADED=1

# shellcheck source=lib/core.sh
source "${SPFX_DIR}/lib/core.sh"

# ── Directory layout ──────────────────────────────────────────────────────────
# state/
# ├── snapshots/        versions.env snapshots (one per upgrade attempt)
# ├── rollback/         rollback.env → active rollback candidate + metadata JSON
# └── verify-cache/     last-verify.json → cached verification result + timestamp

STATE_DIR="${SPFX_DIR}/state"
SNAPSHOT_DIR="${STATE_DIR}/snapshots"
ROLLBACK_DIR="${STATE_DIR}/rollback"
VERIFY_CACHE_DIR="${STATE_DIR}/verify-cache"

state_init() {
    mkdir -p "$SNAPSHOT_DIR" "$ROLLBACK_DIR" "$VERIFY_CACHE_DIR"
    log_debug "State dirs initialized: $STATE_DIR"
}

# ── Snapshot ──────────────────────────────────────────────────────────────────
# state_snapshot_create [label]
# Creates a timestamped snapshot of versions.env.
# Prints the snapshot file path on stdout.
state_snapshot_create() {
    local label="${1:-manual}"
    state_init
    local ts; ts="$(date '+%Y%m%dT%H%M%S')"
    local snap="${SNAPSHOT_DIR}/versions-${ts}-${label}.env"
    cp "${SPFX_DIR}/versions.env" "$snap"
    log_debug "Snapshot created: $snap"
    echo "$snap"
}

# state_snapshot_list
# Lists all snapshots, newest first.
state_snapshot_list() {
    state_init
    local snaps
    snaps="$(find "$SNAPSHOT_DIR" -name 'versions-*.env' | sort -r)"
    if [[ -z "$snaps" ]]; then
        echo "  (no snapshots)"
    else
        echo "$snaps"
    fi
}

# state_snapshot_latest
# Prints path to most recent snapshot, or empty string if none.
state_snapshot_latest() {
    state_init
    find "$SNAPSHOT_DIR" -name 'versions-*.env' | sort -r | head -1
}

# ── Rollback metadata ─────────────────────────────────────────────────────────
# Written before every upgrade attempt so rollback is always possible,
# even if the process is killed mid-flight.
#
# rollback/active.env  → copy of versions.env before the upgrade
# rollback/meta.json   → JSON with ts, label, node, spfx, heft before/after

state_rollback_arm() {
    local label="${1:-upgrade}"
    state_init
    spfx_load_versions

    cp "${SPFX_DIR}/versions.env" "${ROLLBACK_DIR}/active.env"

    # Persist arm-time values so commit/exec can rewrite the JSON without
    # parsing it. Shell-sourceable; values are printf %q-quoted for safety.
    printf 'ROLLBACK_TS=%q\nROLLBACK_LABEL=%q\nROLLBACK_NODE=%q\nROLLBACK_SPFX=%q\n' \
        "$(date -Iseconds)" "${label}" "${NODE_VERSION}" "${SPFX_GENERATOR_VERSION}" \
        > "${ROLLBACK_DIR}/arm.env"
    # shellcheck source=/dev/null
    source "${ROLLBACK_DIR}/arm.env"

    cat > "${ROLLBACK_DIR}/meta.json" << JSON
{
  "timestamp": "${ROLLBACK_TS}",
  "label": "${ROLLBACK_LABEL}",
  "before": {
    "NODE_VERSION": "${ROLLBACK_NODE}",
    "SPFX_GENERATOR_VERSION": "${ROLLBACK_SPFX}"
  },
  "status": "in-progress"
}
JSON
    log_debug "Rollback armed: ${ROLLBACK_DIR}/meta.json"
}

# state_rollback_commit
# Marks the rollback metadata as succeeded. Called after a successful upgrade.
state_rollback_commit() {
    [[ -f "${ROLLBACK_DIR}/arm.env" ]] || return 0
    # arm.env was written by state_rollback_arm — source it instead of parsing
    # meta.json, which avoids any fragile grep/awk over JSON text.
    # Declare locals first so sourced vars stay in function scope.
    local ROLLBACK_TS="" ROLLBACK_LABEL="" ROLLBACK_NODE="" ROLLBACK_SPFX=""
    # shellcheck source=/dev/null
    source "${ROLLBACK_DIR}/arm.env"
    cat > "${ROLLBACK_DIR}/meta.json" << JSON
{
  "timestamp": "${ROLLBACK_TS}",
  "label": "${ROLLBACK_LABEL}",
  "before": {
    "NODE_VERSION": "${ROLLBACK_NODE}",
    "SPFX_GENERATOR_VERSION": "${ROLLBACK_SPFX}"
  },
  "status": "committed"
}
JSON
    log_debug "Rollback committed"
}

# state_rollback_exec
# Restores versions.env from the armed rollback copy.
# Used inside ERR trap — must not itself fail. Never exits non-zero.
state_rollback_exec() {
    if [[ -f "${ROLLBACK_DIR}/active.env" ]]; then
        cp "${ROLLBACK_DIR}/active.env" "${SPFX_DIR}/versions.env" || true
        # Source arm.env to get the original values without parsing meta.json.
        # Declare locals with safe defaults in case arm.env is missing/corrupt.
        local ROLLBACK_TS="" ROLLBACK_LABEL="" ROLLBACK_NODE="" ROLLBACK_SPFX=""
        if [[ -f "${ROLLBACK_DIR}/arm.env" ]]; then
            # shellcheck source=/dev/null
            source "${ROLLBACK_DIR}/arm.env" 2>/dev/null || true
        fi
        cat > "${ROLLBACK_DIR}/meta.json" << JSON 2>/dev/null || true
{
  "timestamp": "${ROLLBACK_TS}",
  "label": "${ROLLBACK_LABEL}",
  "before": {
    "NODE_VERSION": "${ROLLBACK_NODE}",
    "SPFX_GENERATOR_VERSION": "${ROLLBACK_SPFX}"
  },
  "status": "rolled-back"
}
JSON
        log_warn "Rollback applied from: ${ROLLBACK_DIR}/active.env"
    else
        log_err "Rollback requested but no armed state found: ${ROLLBACK_DIR}/active.env"
    fi
}


# state_rollback_status
# Prints human-readable rollback state.
state_rollback_status() {
    local meta="${ROLLBACK_DIR}/meta.json"
    if [[ ! -f "$meta" ]]; then
        echo "  No rollback state recorded."
        return
    fi
    echo "  Rollback state: ${meta}"
    cat "$meta"
}

# ── Verification cache ────────────────────────────────────────────────────────
# Cache avoids re-running the expensive container verification on every command.
# TTL: 1 hour (3600 seconds). Cache is invalidated on bootstrap or upgrade.
VERIFY_CACHE_FILE="${VERIFY_CACHE_DIR}/last-verify.json"
VERIFY_CACHE_TTL=3600

# state_verify_cache_write <exit_code>
# Records the result of spfx-verify with a timestamp.
state_verify_cache_write() {
    local rc="${1:-0}"
    state_init
    cat > "$VERIFY_CACHE_FILE" << JSON
{
  "timestamp": "$(date -Iseconds)",
  "epoch": $(date '+%s'),
  "exit_code": ${rc},
  "node_version": "${NODE_VERSION:-unknown}",
  "spfx_version": "${SPFX_GENERATOR_VERSION:-unknown}"
}
JSON
    log_debug "Verify cache written (rc=${rc})"
}

# state_verify_cache_valid
# Returns 0 if a fresh passing cache exists, 1 otherwise.
state_verify_cache_valid() {
    [[ -f "$VERIFY_CACHE_FILE" ]] || return 1

    local cached_epoch cached_rc
    # Extract epoch without jq (grep + awk)
    cached_epoch="$(grep '"epoch"' "$VERIFY_CACHE_FILE" | awk -F': ' '{print $2}' | tr -d ',')"
    cached_rc="$(grep '"exit_code"' "$VERIFY_CACHE_FILE" | awk -F': ' '{print $2}' | tr -d ',')"

    [[ -n "$cached_epoch" && -n "$cached_rc" ]] || return 1
    [[ "$cached_rc" -eq 0 ]] || return 1   # cached failure always re-verify

    local now; now="$(date '+%s')"
    local age=$(( now - cached_epoch ))
    log_debug "Verify cache age: ${age}s (TTL: ${VERIFY_CACHE_TTL}s)"
    [[ "$age" -ge 0 && "$age" -lt "$VERIFY_CACHE_TTL" ]]
}

# state_verify_cache_invalidate
# Call after bootstrap or upgrade to force a fresh verify.
state_verify_cache_invalidate() {
    rm -f "$VERIFY_CACHE_FILE"
    log_debug "Verify cache invalidated"
}
