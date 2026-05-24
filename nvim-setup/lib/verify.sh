#!/usr/bin/env bash
# nvim-verify — check the whole setup is healthy and executable. Read-only.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../versions.env"

G='\033[32m'; R='\033[31m'; C='\033[36m'; B='\033[1m'; Z='\033[0m'
ok()   { printf "${G}  ✔  %s${Z}\n" "$1"; }
bad()  { printf "${R}  ✗  %s${Z}\n" "$1"; FAIL=1; }
section() { printf "\n${B}══ %s ══${Z}\n" "$1"; }
FAIL=0

section "nvim-setup verification"

# 1. nvim binary + version
if command -v nvim >/dev/null; then
  ok "nvim: $(nvim --version | head -1 | awk '{print $2}')"
else bad "nvim not in PATH"; fi

# 2. config loads with no errors
if nvim --headless -c 'qa' >/dev/null 2>&1; then ok "config loads clean"
else bad "config has load errors"; fi

# 3. plugins present
PC=$(nvim --headless -c 'lua io.write(#require("lazy").plugins())' -c 'qa' 2>/dev/null)
[ "${PC:-0}" -ge 1 ] && ok "plugins loaded: $PC" || bad "no plugins loaded"

# 4. LSP server binaries (from the single source of truth)
SERVERS_LUA="$HOME/scripts/nvim-setup/lib/servers.lua"
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  if command -v "$cmd" >/dev/null; then ok "LSP server: $cmd"
  else bad "LSP server: missing binary '$cmd'"; fi
done < <(grep -oE 'cmd = "[^"]+"' "$SERVERS_LUA" | sed 's/cmd = "//; s/"$//')

# 5. clipboard backend (clipso) reachable
CLIPSO="$HOME/scripts/clipso/clipso.sh"
[ -x "$CLIPSO" ] && ok "clipboard: clipso executable" || bad "clipso not executable at $CLIPSO"

section "result"
[ "$FAIL" -eq 0 ] && { ok "All checks passed."; exit 0; } || { bad "Some checks failed."; exit 1; }
