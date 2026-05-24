#!/usr/bin/env bash
# resolve-bin.sh — ensure a server binary is callable.
# Strategy: PATH first; fallback to locating the package's bin .js and wrapping it.
set -uo pipefail

# resolve_bin <command-name> [npm-package-hint]
# echoes the resolved path on success, creates a ~/.local/bin wrapper if needed.
resolve_bin() {
  local cmd="$1" pkg="${2:-$1}"
  # 1. already in PATH
  if command -v "$cmd" >/dev/null 2>&1; then command -v "$cmd"; return 0; fi

  local prefix moddir
  prefix="$(npm config get prefix 2>/dev/null)"
  moddir="$prefix/lib/node_modules"

  # 2. find the package's declared bin via its package.json
  local pkgjson="$moddir/$pkg/package.json"
  local target=""
  if [ -f "$pkgjson" ]; then
    # extract bin path for this cmd (node, no jq dependency)
    target="$(node -e '
      const p=require(process.argv[1]); const c=process.argv[2];
      let b=p.bin; if(typeof b==="string") b={[p.name]:b};
      const rel=b&&(b[c]||b[Object.keys(b)[0]]); if(rel) process.stdout.write(rel);
    ' "$pkgjson" "$cmd" 2>/dev/null)"
  fi

  if [ -n "$target" ] && [ -f "$moddir/$pkg/$target" ]; then
    local wrapper="$HOME/.local/bin/$cmd"
    mkdir -p "$HOME/.local/bin"
    printf '#!/usr/bin/env bash\nexec node "%s/%s/%s" "$@"\n' "$moddir" "$pkg" "$target" > "$wrapper"
    chmod +x "$wrapper"
    hash -r 2>/dev/null || true
    printf '%s\n' "$wrapper"
    return 0
  fi
  return 1
}
