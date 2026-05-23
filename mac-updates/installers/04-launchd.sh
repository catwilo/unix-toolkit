#!/usr/bin/env bash
# 04-launchd.sh — registra el agente launchd que arranca la VM al login.
# Flujo reboot: launchd → wrapper (carga Nix + PATH) → mac-updates start → tmux → QEMU
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/lib/ui/output.sh"
source "$ROOT_DIR/lib/core/env.sh"

mkdir -p "$(dirname "$PLIST_PATH")" "$MAC_UPDATES_ROOT/vm" "$MAC_UPDATES_ROOT/logs"

# ── Wrapper script ────────────────────────────────────────────────────────────
# launchd arranca con entorno mínimo — este wrapper carga Nix y llama
# 'mac-updates start', que crea la sesión tmux y lanza QEMU.
WRAPPER="$MAC_UPDATES_ROOT/vm/launchd-start.sh"
cat > "$WRAPPER" << WRAPPER_EOF
#!/bin/bash
# Generado por install.sh — no editar manualmente.

# Cargar entorno Nix
for _nix_sh in \\
  "\$HOME/.nix-profile/etc/profile.d/nix.sh" \\
  "/nix/var/nix/profiles/default/etc/profile.d/nix.sh"; do
  [[ -f "\$_nix_sh" ]] && source "\$_nix_sh" && break
done

export PATH="${ROOT_DIR}/bin:\$PATH"

# Garantizar profile minimal en cada arranque
echo "minimal" > "${MAC_UPDATES_ROOT}/vm/current-profile"

exec "${ROOT_DIR}/bin/mac-updates" start
WRAPPER_EOF
chmod +x "$WRAPPER"

# ── Plist ─────────────────────────────────────────────────────────────────────
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${WRAPPER}</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>USER</key>
    <string>${USER}</string>
    <key>PATH</key>
    <string>${ROOT_DIR}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <false/>

  <key>StandardOutPath</key>
  <string>${LOG_OUT}</string>

  <key>StandardErrorPath</key>
  <string>${LOG_ERR}</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load   "$PLIST_PATH"
print_success "launchd agent registrado (${PLIST_LABEL})"
