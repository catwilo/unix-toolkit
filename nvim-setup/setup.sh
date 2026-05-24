#!/usr/bin/env bash
# nvim-setup — full idempotent installer with snapshot/rollback + bin resolution.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/versions.env"
# shellcheck disable=SC1091
source "$HERE/lib/state.sh"
# shellcheck disable=SC1091
source "$HERE/lib/resolve-bin.sh"

G='\033[32m'; R='\033[31m'; C='\033[36m'; Y='\033[33m'; B='\033[1m'; Z='\033[0m'
ok()   { printf "${G}  ✔  %s${Z}\n" "$1"; }
err()  { printf "${R}  ✗  %s${Z}\n" "$1" >&2; }
info() { printf "${C}  →  %s${Z}\n" "$1"; }
warn() { printf "${Y}  !  %s${Z}\n" "$1"; }
step() { printf "\n${B}══ %s ══${Z}\n" "$1"; }

command -v nvim >/dev/null || { err "nvim not in PATH"; exit 1; }
command -v npm  >/dev/null || { err "npm not in PATH — load nvm first"; exit 1; }

step "0/5  Snapshot current versions (for rollback)"
snapshot_versions && ok "snapshot saved"

step "1/5  Syncing nvim plugins"
nvim --headless "+Lazy! sync" +qa 2>&1 | grep -iE 'error|fail' | grep -vE 'deprecated' || true
ok "plugins synced"

step "2/5  Installing pinned npm LSP servers"
PREFIX="$(npm config get prefix)"; MODDIR="$PREFIX/lib/node_modules"
for spec in "${NPM_LSP_SERVERS[@]}"; do
  pkg="${spec%@*}"; want="${spec#*@}"
  have="$(npm ls -g --depth=0 "$pkg" 2>/dev/null | sed -n "s/.*${pkg}@//p" | head -1)"
  if [ "$have" = "$want" ]; then ok "$spec (present)"; continue; fi
  [ -e "$MODDIR/$pkg" ] && rm -rf "${MODDIR:?}/$pkg" "${MODDIR}/.${pkg}-"* 2>/dev/null || true
  info "installing $spec ..."
  npm install -g "$spec" --no-fund --no-audit && ok "$spec" || err "failed: $spec"
done

step "3/5  Resolving server binaries"
while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  if resolve_bin "$cmd" >/dev/null; then ok "$cmd"; else warn "could not resolve $cmd"; fi
done < <(grep -oE 'cmd = "[^"]+"' "$HERE/lib/servers.lua" | sed 's/cmd = "//; s/"$//' | grep -v lua-language-server)

step "4/5  Installing lua-language-server"
bash "$HERE/lib/install-lua-ls.sh"

step "5/5  Verifying"
if bash "$HERE/lib/verify.sh"; then
  ok "Setup complete."
else
  warn "Verification failed — rolling back to previous versions"
  rollback_versions && warn "rolled back; re-run after fixing versions.env"
  exit 1
fi
