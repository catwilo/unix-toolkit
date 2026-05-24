#!/usr/bin/env bash
# Install lua-language-server (prebuilt binary) to ~/.local. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../versions.env"

G='\033[32m'; C='\033[36m'; Z='\033[0m'
ok()   { printf "${G}  ✔  %s${Z}\n" "$1"; }
info() { printf "${C}  →  %s${Z}\n" "$1"; }

DEST="$HOME/.local/lua-language-server"
BIN="$HOME/.local/bin/lua-language-server"

if command -v lua-language-server >/dev/null 2>&1; then
  ok "lua-language-server already in PATH ($(lua-language-server --version 2>/dev/null | head -1))"
  exit 0
fi

V="$LUA_LS_VERSION"
URL="https://github.com/LuaLS/lua-language-server/releases/download/${V}/lua-language-server-${V}-linux-x64.tar.gz"
info "downloading lua-language-server $V"
mkdir -p "$DEST" "$HOME/.local/bin"
curl -L --progress-bar --retry 5 --retry-delay 2 -o /tmp/lua-ls.tar.gz "$URL"
tar -xzf /tmp/lua-ls.tar.gz -C "$DEST"
# wrapper so the binary finds its runtime regardless of CWD
cat > "$BIN" <<WRAP
#!/usr/bin/env bash
exec "$DEST/bin/lua-language-server" "\$@"
WRAP
chmod +x "$BIN"
hash -r
ok "lua-language-server $("$BIN" --version 2>/dev/null | head -1)"
