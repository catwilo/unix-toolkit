#!/usr/bin/env bash
# deps.sh — ensure a healthy Nix and required packages on macOS. Idempotent.
#
# Requires lib/nix.sh sourced for classify_nix_state / _nix_bin.
# Will NOT attempt install if state is 'broken' — caller must repair first.

ensure_nix() {
    local state; state="$(classify_nix_state)"
    case "$state" in
        healthy)
            ok "Nix healthy ($("$(_nix_bin)" --version 2>/dev/null | head -1))"
            return 0 ;;
        broken)
            err "Nix state is 'broken' — run ./repair-nix.sh first, then reboot"
            return 1 ;;
        absent)
            info "Nix absent — installing via Determinate installer"
            warn "this installs a system daemon and requires sudo (interactive)"
            curl --proto '=https' --tlsv1.2 -sSf -L "$NIX_INSTALLER_URL" \
                | sh -s -- install
            # Determinate sets up the daemon; load it into THIS shell.
            # shellcheck disable=SC1091
            [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ] \
                && . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
            classify_nix_state | grep -q healthy \
                && { ok "Nix installed"; return 0; } \
                || { err "Nix install did not reach healthy state"; return 1; } ;;
    esac
}

ensure_packages() {
    local nix; nix="$(_nix_bin)" || { err "nix binary not found"; return 1; }
    local spec installed
    installed="$("$nix" profile list 2>/dev/null || true)"
    for spec in "${NIX_PACKAGES[@]}"; do
        if printf '%s\n' "$installed" | grep -qF "$spec"; then
            ok "$spec (present)"
            continue
        fi
        info "installing $spec ..."
        "$nix" profile install "$spec" && ok "$spec" || err "failed: $spec"
    done
}
