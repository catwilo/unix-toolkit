#!/usr/bin/env bash
# repair-nix.sh — clean up a BROKEN Nix install on macOS (volume + daemons +
# synthetic.conf + fstab present, but /nix/store unpopulated).
#
# SAFETY: every destructive step is gated behind an explicit `yes`. Nothing
# runs in cascade. A snapshot of current state is written first for reference.
# Run ONLY after classify_nix_state reports `broken`. Requires sudo.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/nix.sh"
G='\033[32m'; R='\033[31m'; C='\033[36m'; Y='\033[33m'; B='\033[1m'; Z='\033[0m'
ok()   { printf "${G}  ✔  %s${Z}\n" "$1"; }
err()  { printf "${R}  ✗  %s${Z}\n" "$1" >&2; }
info() { printf "${C}  →  %s${Z}\n" "$1"; }
warn() { printf "${Y}  !  %s${Z}\n" "$1"; }
step() { printf "\n${B}══ %s ══${Z}\n" "$1"; }

confirm_step() {
    # $1 = description shown before asking
    printf "${Y}  ?  %s${Z}\n" "$1"
    printf "     type 'yes' to run this step (anything else skips): "
    local a; read -r a
    [ "$a" = "yes" ]
}

[ "$(uname)" = "Darwin" ] || { err "repair-nix is macOS-only"; exit 1; }

state="$(classify_nix_state)"
[ "$state" = "broken" ] || { err "state is '$state', not 'broken' — refusing to run"; exit 1; }

step "0  Snapshot current Nix infra state"
SNAP="$HERE/state"; mkdir -p "$SNAP"
SNAPFILE="$SNAP/nix-repair-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "# repair-nix snapshot $(date)"
    echo "## launchdaemons"; ls -l /Library/LaunchDaemons/org.nixos.*.plist 2>/dev/null || true
    echo "## synthetic.conf"; cat /etc/synthetic.conf 2>/dev/null || true
    echo "## fstab"; cat /etc/fstab 2>/dev/null || true
    echo "## apfs nix volume"; diskutil apfs list 2>/dev/null | grep -B3 -i 'Nix Store' || true
} > "$SNAPFILE"
ok "snapshot → $SNAPFILE"

step "1  Bootout + remove LaunchDaemons"
if confirm_step "unload and delete /Library/LaunchDaemons/org.nixos.*.plist (sudo)"; then
    for d in nix-daemon darwin-store; do
        sudo launchctl bootout "system/org.nixos.$d" 2>/dev/null || true
    done
    sudo rm -f /Library/LaunchDaemons/org.nixos.nix-daemon.plist \
               /Library/LaunchDaemons/org.nixos.darwin-store.plist
    ok "daemons unloaded + plists removed"
else
    warn "skipped daemon removal"
fi

step "2  Clean /etc/synthetic.conf"
if grep -q '^nix$' /etc/synthetic.conf 2>/dev/null; then
    if confirm_step "remove the 'nix' line from /etc/synthetic.conf (sudo)"; then
        # remove only the bare 'nix' line; preserve any other entries
        sudo sed -i '' '/^nix$/d' /etc/synthetic.conf
        # if file is now empty, remove it
        [ -s /etc/synthetic.conf ] || sudo rm -f /etc/synthetic.conf
        ok "synthetic.conf cleaned"
    else
        warn "skipped synthetic.conf"
    fi
else
    info "no 'nix' entry in synthetic.conf — nothing to do"
fi

step "3  Clean /etc/fstab"
if grep -qi '/nix' /etc/fstab 2>/dev/null; then
    if confirm_step "remove the /nix line from /etc/fstab (sudo)"; then
        sudo sed -i '' '/[[:space:]]\/nix[[:space:]]/d' /etc/fstab
        ok "fstab cleaned"
    else
        warn "skipped fstab"
    fi
else
    info "no /nix entry in fstab — nothing to do"
fi

step "4  Delete the 'Nix Store' APFS volume"
if diskutil apfs list 2>/dev/null | grep -qi 'Name:.*Nix Store'; then
    warn "this destroys the /nix volume — irreversible"
    if confirm_step "diskutil apfs deleteVolume 'Nix Store' (sudo)"; then
        sudo diskutil apfs deleteVolume "Nix Store"
        ok "Nix Store volume deleted"
    else
        warn "skipped volume deletion"
    fi
else
    info "no 'Nix Store' volume found — nothing to do"
fi

step "Done"
info "a reboot is recommended to fully clear the synthetic /nix mountpoint"
info "after reboot, re-run setup-mac to install a clean Nix"
