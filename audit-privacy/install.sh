#!/usr/bin/env bash
# audit-privacy/install.sh — idempotent installer
#
# usage:
#   bash install.sh          install
#   bash install.sh verify   verify only (no changes)
#
# Compatible: Termux (no-root), Debian, Raspbian, macOS

set -Eeuo pipefail

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m' YELLOW='\033[1;33m' GREEN='\033[0;32m' CYAN='\033[0;36m' RESET='\033[0m'
else
    RED='' YELLOW='' GREEN='' CYAN='' RESET=''
fi
ok()   { printf "${GREEN}[OK]${RESET}    %s\n" "$*" >&2; }
warn() { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*" >&2; }
info() { printf "${CYAN}[INFO]${RESET}  %s\n" "$*" >&2; }
die()  { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }

# -- Resolve script dir (symlink-safe, macOS+Linux+Termux) --------------------
_self="$0"
case "$_self" in */*) ;; *) _self="$(command -v "$_self")" ;; esac
if _real="$(readlink -f "$_self" 2>/dev/null)" && [ -n "$_real" ]; then
    _self="$_real"
else
    while [ -L "$_self" ]; do
        _link="$(readlink "$_self")"
        case "$_link" in /*) _self="$_link" ;; *) _self="$(dirname "$_self")/$_link" ;; esac
    done
fi
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd -P)"
TOOL="$SCRIPT_DIR/audit-privacy.sh"

[ -f "$TOOL" ] || die "audit-privacy.sh not found at $TOOL"
[ -x "$TOOL" ] || chmod +x "$TOOL"

# -- Resolve bin dir (no-root friendly) ---------------------------------------
_bin_dir() {
    for d in "$HOME/.local/bin" "$HOME/bin" "$PREFIX/bin"; do
        [ -d "$d" ] && { echo "$d"; return; }
    done
    # fallback: create ~/.local/bin
    mkdir -p "$HOME/.local/bin"
    echo "$HOME/.local/bin"
}

BIN_DIR="$(_bin_dir)"
LINK="$BIN_DIR/audit-privacy"

# -- Verify -------------------------------------------------------------------
_do_verify() {
    local found target
    found="$(command -v audit-privacy 2>/dev/null || true)"
    [ -n "$found" ] || { warn "audit-privacy not in PATH — source your shell rc"; return 1; }
    target="$(readlink -f "$found" 2>/dev/null || echo "$found")"
    [ "$target" = "$TOOL" ] || { warn "audit-privacy -> $target (expected $TOOL)"; return 1; }
    ok "audit-privacy -> $TOOL"
}

if [ "${1:-}" = "verify" ]; then
    _do_verify
    exit $?
fi

# -- Install ------------------------------------------------------------------
info "installing audit-privacy -> $LINK"

# Remove stale link if pointing elsewhere
if [ -L "$LINK" ]; then
    old="$(readlink -f "$LINK" 2>/dev/null || true)"
    [ "$old" = "$TOOL" ] && { ok "already installed"; _do_verify; exit 0; }
    rm "$LINK"
fi
[ -e "$LINK" ] && die "$LINK exists and is not a symlink — remove manually"

ln -s "$TOOL" "$LINK"
ok "symlink created: $LINK -> $TOOL"

# -- PATH hint ----------------------------------------------------------------
case ":${PATH}:" in
    *":$BIN_DIR:"*) ;;
    *)
        warn "$BIN_DIR not in PATH"
        info "add to your shell rc:  export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac

_do_verify
ok "done — run: audit-privacy [dir...]"
