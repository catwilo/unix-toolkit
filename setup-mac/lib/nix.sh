#!/usr/bin/env bash
# nix.sh — Nix state detection (read-only) for setup-mac.
#
# classify_nix_state echoes exactly one of:
#   absent   — no /nix volume, no daemons, no store
#   broken   — infra present (volume/daemons/synthetic) but store unpopulated
#   healthy  — nix binary resolvable AND store populated
#
# All checks are read-only. No mutation here. Callers decide what to do.

# Resolve the nix binary across the known install layouts without assuming PATH.
_nix_bin() {
    local c
    for c in \
        /nix/var/nix/profiles/default/bin/nix \
        "$HOME/.nix-profile/bin/nix" \
        /run/current-system/sw/bin/nix; do
        [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
    done
    command -v nix 2>/dev/null && return 0
    return 1
}

# Does the store contain at least one nix binary package?
_store_populated() {
    # A healthy store always has nix itself realised.
    ls /nix/store/*/bin/nix >/dev/null 2>&1
}

_nix_volume_present() {
    diskutil apfs list 2>/dev/null | grep -qi 'Name:.*Nix Store'
}

_nix_daemons_present() {
    ls /Library/LaunchDaemons/org.nixos.*.plist >/dev/null 2>&1
}

_nix_synthetic_present() {
    grep -q '^nix$' /etc/synthetic.conf 2>/dev/null
}

classify_nix_state() {
    if _nix_bin >/dev/null 2>&1 && _store_populated; then
        printf 'healthy\n'; return 0
    fi
    if _nix_volume_present || _nix_daemons_present || _nix_synthetic_present || [ -d /nix ]; then
        printf 'broken\n'; return 0
    fi
    printf 'absent\n'
}
