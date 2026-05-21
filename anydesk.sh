#!/usr/bin/env bash
# anydesk — AnyDesk client in a rootless Podman container (X11)
# Install: cp anydesk ~/.local/bin/anydesk && chmod +x ~/.local/bin/anydesk
# Usage:   anydesk [run|setup|rebuild|logs|help]

set -Eeuo pipefail

# ── Config ────────────────────────────────────────────────────────────
readonly IMAGE="anydesk-client"
readonly DEB_URL="https://download.anydesk.com/linux/anydesk_6.4.0-1_amd64.deb"
readonly DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/anydesk-container"

# ── Output helpers ────────────────────────────────────────────────────
ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }
info() { printf '\033[0;34m→ %s\033[0m\n' "$*"; }
warn() { printf '\033[0;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── Environment validation ────────────────────────────────────────────
check_env() {
    command -v podman &>/dev/null     || die "podman not found"
    [[ -n "${DISPLAY:-}" ]]           || die "DISPLAY unset"
    [[ -S /tmp/.X11-unix/X${DISPLAY##*:} ]] \
                                      || die "X11 socket missing for $DISPLAY"
    [[ -f "$HOME/.Xauthority" ]]      || die ".Xauthority missing"
    DISPLAY="$DISPLAY" xset q &>/dev/null \
                                      || die "X server $DISPLAY not responding"
}

# ── Inline Containerfile ──────────────────────────────────────────────
# NOTE: Written for /bin/sh (dash) — the default in debian:bookworm-slim.
# The SHELL instruction is intentionally omitted; bash is not guaranteed
# present at build time and is not needed here.
containerfile() {
    cat <<'DOCKERFILE'
FROM debian:bookworm-slim

ARG DEB_URL
ENV DEBIAN_FRONTEND=noninteractive

# Block service auto-start during install (policy-rc.d approach, POSIX sh).
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
 && chmod +x /usr/sbin/policy-rc.d

# Install deps + AnyDesk in one layer; clean apt cache in same RUN.
# Two-step dpkg pattern: install, fix broken, configure — no bare '|| true'.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      wget \
      xauth \
      libgtk-3-0 \
      libxdamage1 \
      libxfixes3 \
      libxrandr2 \
      libxkbcommon0 \
      libgbm1 \
      libpango-1.0-0 \
      libpangocairo-1.0-0 \
      libcairo2 \
      libasound2 \
      libnss3 \
      libx11-6 \
      libxext6 \
      libxtst6 \
      dbus-x11 \
      procps \
 && wget -qO /tmp/anydesk.deb "$DEB_URL" \
 && dpkg -i /tmp/anydesk.deb ; apt-get install -fy --no-install-recommends \
 && dpkg --configure -a \
 && rm -f /tmp/anydesk.deb \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENTRYPOINT ["anydesk"]
DOCKERFILE
}

# ── Build image ───────────────────────────────────────────────────────
setup() {
    podman image exists "$IMAGE" && { ok "image '$IMAGE' already present"; return; }

    info "building '$IMAGE' (first run, ~2 min)…"

    local build_ctx
    build_ctx=$(mktemp -d)
    trap "rm -rf \"$build_ctx\"" RETURN

    # Pass Containerfile via stdin — no build context needed.
    containerfile | podman build \
        --pull=newer \
        --build-arg "DEB_URL=$DEB_URL" \
        --no-cache=false \
        -t "$IMAGE" \
        -f - "$build_ctx" \
        || die "image build failed"

    podman run --rm "$IMAGE" which anydesk &>/dev/null \
        || die "post-build sanity check failed: anydesk binary not found"

    ok "image '$IMAGE' ready"
}

# ── Force rebuild ─────────────────────────────────────────────────────
rebuild() {
    if podman image exists "$IMAGE"; then
        podman image rm -f "$IMAGE" >/dev/null
        warn "old image removed"
    fi
    setup
}

# ── Run AnyDesk ───────────────────────────────────────────────────────
run() {
    check_env
    setup
    mkdir -p "$DATA_DIR"

    # Derive display number cleanly for the socket path.
    local display_num="${DISPLAY##*:}"
    local x11_socket="/tmp/.X11-unix/X${display_num%%.*}"

    info "launching AnyDesk…"

    local exit_code=0
    podman run --rm \
        --userns=keep-id \
        --security-opt label=disable \
        --network=host \
        -e DISPLAY="$DISPLAY" \
        -e XAUTHORITY=/tmp/.Xauthority \
        -e DBUS_SESSION_BUS_ADDRESS=/dev/null \
        -v "${x11_socket}:${x11_socket}:ro" \
        -v "$HOME/.Xauthority:/tmp/.Xauthority:ro" \
        -v "$DATA_DIR:/root/.anydesk:Z" \
        "$IMAGE" || exit_code=$?

    if (( exit_code == 0 )); then
        ok "AnyDesk exited cleanly"
    else
        warn "AnyDesk exited with status $exit_code"
    fi
}

# ── Logs ──────────────────────────────────────────────────────────────
logs() {
    local trace="$DATA_DIR/anydesk.trace"
    if [[ -f "$trace" ]]; then
        tail -40 "$trace"
    else
        warn "no trace file at $trace"
    fi
}

# ── Help ──────────────────────────────────────────────────────────────
help() {
    cat <<EOF
anydesk — rootless Podman AnyDesk client

  run      Launch client (default)
  setup    Build image if missing
  rebuild  Force full image rebuild
  logs     Tail last 40 lines of trace log
  help     Show this help
EOF
}

# ── Entrypoint ────────────────────────────────────────────────────────
case "${1:-run}" in
    run)     run     ;;
    setup)   setup   ;;
    rebuild) rebuild ;;
    logs)    logs    ;;
    help)    help    ;;
    *)       die "unknown command '$1' — run 'anydesk help'" ;;
esac
