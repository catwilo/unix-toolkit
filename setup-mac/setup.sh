#!/usr/bin/env bash
# setup-mac — bootstrap a fresh/empty Mac with Nix + deps + PATH wiring.
# Idempotent. Acotated scope: detect → (guide repair) → Nix → nmap → PATH.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/versions.env"
# shellcheck disable=SC1091
source "$HERE/lib/nix.sh"
# shellcheck disable=SC1091
source "$HERE/lib/deps.sh"
# shellcheck disable=SC1091
source "$HERE/lib/path.sh"
G='\033[32m'; R='\033[31m'; C='\033[36m'; Y='\033[33m'; B='\033[1m'; Z='\033[0m'
ok()   { printf "${G}  ✔  %s${Z}\n" "$1"; }
err()  { printf "${R}  ✗  %s${Z}\n" "$1" >&2; }
info() { printf "${C}  →  %s${Z}\n" "$1"; }
warn() { printf "${Y}  !  %s${Z}\n" "$1"; }
step() { printf "\n${B}══ %s ══${Z}\n" "$1"; }

[ "$(uname)" = "Darwin" ] || { err "setup-mac is macOS-only"; exit 1; }

step "1/4  Detect Nix state"
state="$(classify_nix_state)"
info "Nix state: $state"
if [ "$state" = "broken" ]; then
    err "Nix install is broken. Run:  ./repair-nix.sh   then reboot, then re-run setup."
    exit 1
fi

step "2/4  Ensure Nix"
ensure_nix || exit 1

step "3/4  Ensure packages (${NIX_PACKAGES[*]})"
ensure_packages

step "4/4  Wire PATH for non-interactive shells"
ensure_path_zshenv

step "Done"
ok "setup-mac complete — open a new SSH session to pick up PATH"
