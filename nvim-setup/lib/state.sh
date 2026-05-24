#!/usr/bin/env bash
# state.sh — version snapshot & rollback for global npm LSP servers.
# Sourced by setup.sh; can also run standalone: state.sh snapshot|rollback|show
set -uo pipefail
STATE_DIR="$HOME/.local/state/nvim-setup"
SNAP="$STATE_DIR/versions.lock"

_pkgs() {
  # packages we manage, names only (from versions.env NPM_LSP_SERVERS)
  local s
  for s in "${NPM_LSP_SERVERS[@]}"; do printf '%s\n' "${s%@*}"; done
}

snapshot_versions() {
  mkdir -p "$STATE_DIR"
  : > "$SNAP"
  local pkg ver
  while IFS= read -r pkg; do
    ver="$(npm ls -g --depth=0 "$pkg" 2>/dev/null | sed -n "s/.*${pkg}@//p" | head -1)"
    [ -n "$ver" ] && printf '%s@%s\n' "$pkg" "$ver" >> "$SNAP"
  done < <(_pkgs)
}

rollback_versions() {
  [ -s "$SNAP" ] || { echo "no snapshot to roll back to"; return 1; }
  local spec
  while IFS= read -r spec; do
    [ -n "$spec" ] && npm install -g "$spec" --no-fund --no-audit
  done < "$SNAP"
}

show_snapshot() { [ -s "$SNAP" ] && cat "$SNAP" || echo "(no snapshot)"; }

# standalone dispatch
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$HERE/../versions.env"
  case "${1:-show}" in
    snapshot) snapshot_versions && echo "snapshot saved to $SNAP" ;;
    rollback) rollback_versions ;;
    show)     show_snapshot ;;
    *) echo "usage: state.sh snapshot|rollback|show"; exit 1 ;;
  esac
fi
