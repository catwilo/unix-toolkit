#!/usr/bin/env bash
# uninstall.sh — remove the wifi-setup toolkit and the failover monitor.
# Leaves NetworkManager and your saved networks intact by default.
set -Eeuo pipefail
IFS=$'\n\t'

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SRC_DIR}/lib/common.sh" 2>/dev/null || {
    WS_BASE="/opt/wifi-setup"; WS_BIN="${WS_BASE}/bin"
    ok(){ printf '✓ %s\n' "$*"; }; info(){ printf '→ %s\n' "$*"; }; warn(){ printf '! %s\n' "$*"; }
}

[[ "${EUID}" -eq 0 ]] || { echo "ejecuta como root" >&2; exit 1; }

USER_BINS=(wifi-add wifi-saved wifi-rm wifi-connect wifi-status wifi-list \
           wifi-showpass wifi-passwd wifi-prefer wifi-failover wifi-panic \
           wifi-tailscale wifi-mac wifi-doctor)

info "deteniendo monitor de failover…"
systemctl disable --now wifi-failover.timer   >/dev/null 2>&1 || true
systemctl disable --now wifi-failover.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/wifi-failover.service /etc/systemd/system/wifi-failover.timer
systemctl daemon-reload
ok "monitor eliminado"

info "eliminando symlinks…"
for b in "${USER_BINS[@]}"; do rm -f "/usr/local/bin/${b}"; done
ok "comandos retirados del PATH"

rm -f /etc/NetworkManager/conf.d/10-wifi-setup.conf
rm -f /etc/NetworkManager/conf.d/90-no-mac-rand.conf
systemctl reload NetworkManager >/dev/null 2>&1 || true
ok "configuración NM de wifi-setup eliminada"

echo
warn "se conserva ${WS_BASE} (logs/estado) y tus redes guardadas en NetworkManager."
echo "Tailscale (si lo instalaste) NO se toca — sigue funcionando."
echo "para borrar todo:        rm -rf ${WS_BASE}"
echo "para borrar una red:     nmcli connection delete <ssid>"
echo "para quitar Tailscale:   tailscale down && apt remove tailscale"
ok "desinstalación completa"
