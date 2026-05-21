#!/usr/bin/env bash
# install.sh — SSH-safe, step-verified install of the NM-based wifi-setup.
#
# SAFETY MODEL (confirmed commit):
#   Over SSH the link carrying our session must survive even if the install
#   fails. We snapshot the working network, arm a SYSTEM-level auto-rollback
#   timer, then change things in an order that never leaves the SSH interface
#   without a manager. Each network-touching step is verified; on any failure
#   we restore immediately. The rollback is disarmed only after final success.
set -Eeuo pipefail
IFS=$'\n\t'

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SRC_DIR}/lib/common.sh"

require_root

USER_BINS=(wifi-add wifi-saved wifi-rm wifi-connect wifi-status wifi-list \
           wifi-showpass wifi-passwd wifi-prefer wifi-failover wifi-panic \
           wifi-tailscale wifi-mac wifi-doctor)
ALL_BINS=("${USER_BINS[@]}" wifi-failover-monitor)

# ── Failure trap: restore network before exiting on any error ────────────────
SAFE_DONE=0
on_error() {
    local code=$?
    [[ "${SAFE_DONE}" -eq 1 ]] && exit "${code}"
    err "fallo en la instalación (código ${code}) — restaurando red previa…"
    [[ -x "${WS_SAFE_DIR}/restore.sh" ]] && "${WS_SAFE_DIR}/restore.sh" || true
    warn "red previa restaurada. El rollback automático sigue armado por si acaso."
    warn "revisa el log: ${WS_LOG}"
    exit "${code}"
}
trap on_error ERR

# ── 0. Prepare state dirs early (needed for snapshot/log) ────────────────────
mkdir -p "${WS_BIN}" "${WS_LIB}" "${WS_STATE}" "${WS_LOG_DIR}" "${WS_SAFE_DIR}"
chmod 700 "${WS_STATE}" "${WS_LOG_DIR}"

SSH_IF="$(ssh_iface)"
if [[ -n "${SSH_IF}" ]]; then
    sep
    warn "sesión SSH detectada por la interfaz: ${SSH_IF}"
    warn "se activará protección con rollback automático (${WS_GRACE_SEC}s)"
    sep
fi

# ── 1. Dependencies (no network change yet) ──────────────────────────────────
info "verificando dependencias…"
apt_updated=0
need_pkg() {
    local cmd="$1" pkg="$2"
    command -v "${cmd}" >/dev/null 2>&1 && { ok "ya presente: ${cmd}"; return; }
    if [[ "${apt_updated}" -eq 0 ]]; then apt-get update -qq || true; apt_updated=1; fi
    info "instalando ${pkg} (para ${cmd})"
    apt-get install -y --no-install-recommends "${pkg}"
}
need_pkg nmcli network-manager
need_pkg curl  curl
need_pkg ip    iproute2

# ── 1b. ASK EVERYTHING UP FRONT — before touching the network ────────────────
# Nothing below this block prompts the user. If SSH drops mid-install, no
# question is left waiting; the work proceeds (and rolls back) on its own.
sep
info "configuración (se preguntará todo ahora, antes de tocar la red)"
DEFAULT_SSID="cursed"
read -r -p "SSID [${DEFAULT_SSID}]: " Q_SSID || Q_SSID=""
Q_SSID="${Q_SSID:-${DEFAULT_SSID}}"

# Password only needed if the profile doesn't already exist.
Q_PASS=""
if ! nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "${Q_SSID}"; then
    Q_PASS="$(read_passphrase)"
fi

read -r -p "IP fija deseada [10.26.35.70] (Enter acepta, 'no' = DHCP): " Q_IP || Q_IP=""
Q_IP="${Q_IP:-10.26.35.70}"
Q_GW=""
if [[ "${Q_IP,,}" != "no" ]]; then
    Q_GW_DEFAULT="$(printf '%s' "${Q_IP}" | sed 's/\.[0-9]*$/.110/')"
    read -r -p "gateway [${Q_GW_DEFAULT}]: " Q_GW || Q_GW=""
    Q_GW="${Q_GW:-${Q_GW_DEFAULT}}"
fi

read -r -p "¿instalar Tailscale? (solo lo deja instalado; tú haces login luego) [s/N]: " Q_TS || Q_TS=""
sep
ok "configuración recogida — a partir de aquí no habrá más preguntas"

# ── 2. Snapshot + arm rollback BEFORE touching the network ───────────────────
snapshot_network
arm_rollback

# ── 3. Bring up NetworkManager WITHOUT removing dhcpcd yet ───────────────────
# Goal: NM starts managing devices while dhcpcd still holds the SSH link, so
# there is never a gap. We tell NM to manage wifi and start it; dhcpcd keeps
# the lease alive in parallel during the transition.
info "configurando NetworkManager (sin tocar dhcpcd todavía)…"
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-wifi-setup.conf <<'EOF'
[main]
plugins=keyfile

[connectivity]
uri=http://nmcheck.gnome.org/check_network_status.txt
interval=20
EOF

# Disable scan-time MAC randomization globally: this is the root fix for the
# "IP changes every few minutes and drops SSH" problem. With a fixed MAC the
# Android hotspot stops handing out a new IP on every reconnect.
cat > /etc/NetworkManager/conf.d/90-no-mac-rand.conf <<'EOF'
[device]
wifi.scan-rand-mac-address=no
EOF

systemctl enable NetworkManager >/dev/null 2>&1 || true
systemctl start  NetworkManager
sleep 2
require_nm
ok "NetworkManager activo (dhcpcd aún presente como respaldo)"

# ── 4. Verify SSH path still alive before the risky step ─────────────────────
if ! ssh_path_alive; then
    die "la interfaz SSH (${SSH_IF}) perdió IP tras iniciar NM — abortando (rollback armado)"
fi
ok "enlace SSH intacto tras iniciar NM"

# ── 5. Deploy files + symlinks (no network change) ───────────────────────────
info "desplegando en ${WS_BASE}…"
cp -a "${SRC_DIR}/bin/." "${WS_BIN}/"
cp -a "${SRC_DIR}/lib/." "${WS_LIB}/"
chmod +x "${WS_BIN}"/wifi-*
for b in "${USER_BINS[@]}"; do ln -sf "${WS_BIN}/${b}" "/usr/local/bin/${b}"; done
ok "binarios, librería y comandos instalados"

# ── 6. Seed first network as a DUAL profile (USB primary + native failover) ──
echo
info "aplicando configuración de red…"
ssid="${Q_SSID}"
usb="$(detect_iface usb)"; native="$(detect_iface native)"
gen_mac() { local h; h="$(printf 'wifi-setup-%s' "${ssid}" | md5sum | cut -c1-6)"; printf '00:1a:2b:%s:%s:%s' "${h:0:2}" "${h:2:2}" "${h:4:2}"; }
PROFILE_MAC="$(gen_mac)"

if nm_profile_exists "${ssid}"; then
    ok "ya existe el perfil '${ssid}' — sin cambios"
else
    # Primary: bound to USB.
    nmcli connection add type wifi con-name "${ssid}" ssid "${ssid}" \
        -- wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${Q_PASS}" \
        connection.interface-name "${usb}" \
        connection.autoconnect yes connection.autoconnect-priority 20 \
        802-11-wireless.cloned-mac-address "${PROFILE_MAC}" >/dev/null
    ok "perfil principal '${ssid}' (USB ${usb}, MAC ${PROFILE_MAC})"

    # Failover twin: bound to native, DHCP.
    if [[ -n "${native}" ]]; then
        nmcli connection add type wifi con-name "${ssid}-failover" ssid "${ssid}" \
            -- wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${Q_PASS}" \
            connection.interface-name "${native}" ipv4.method auto \
            connection.autoconnect yes connection.autoconnect-priority 5 \
            802-11-wireless.cloned-mac-address "${PROFILE_MAC}" >/dev/null
        ok "perfil failover '${ssid}-failover' (nativa ${native}, DHCP)"
    fi
    unset Q_PASS
fi

# Fixed IP on the PRIMARY only, with verify + fallback to DHCP.
if [[ "${Q_IP,,}" == "no" ]]; then
    nmcli connection modify "${ssid}" ipv4.method auto ipv4.addresses "" ipv4.gateway "" >/dev/null 2>&1 || true
    ok "IP por DHCP (MAC fija mantiene la IP estable)"
else
    nmcli connection modify "${ssid}" \
        ipv4.method manual ipv4.addresses "${Q_IP}/24" \
        ipv4.gateway "${Q_GW}" ipv4.dns "1.1.1.1 8.8.8.8" >/dev/null
    nmcli connection up "${ssid}" ifname "${usb}" >/dev/null 2>&1 || true
    sleep 3
    if has_internet ""; then
        ok "IP fija ${Q_IP} activa en USB con Internet"
    else
        warn "IP fija ${Q_IP} sin Internet — revirtiendo a DHCP"
        nmcli connection modify "${ssid}" ipv4.method auto ipv4.addresses "" ipv4.gateway "" >/dev/null
        nmcli connection up "${ssid}" ifname "${usb}" >/dev/null 2>&1 || true
        ok "DHCP restaurado (MAC fija mantiene la IP estable)"
    fi
fi

# ── 7. THE RISKY STEP: hand the SSH interface from dhcpcd to NM ───────────────
# Now retire dhcpcd. NM must immediately take over the SSH interface. We verify
# connectivity right after; if it breaks, restore and abort (rollback also armed).
if systemctl is-active --quiet dhcpcd 2>/dev/null; then
    info "transfiriendo control de red de dhcpcd a NetworkManager…"
    # Ask NM to connect the SSH interface to a known network first if possible,
    # so the lease is continuous. If the SSH iface matches a saved profile, up it.
    if [[ -n "${SSH_IF}" ]]; then
        nmcli device set "${SSH_IF}" managed yes >/dev/null 2>&1 || true
        nmcli device connect "${SSH_IF}" >/dev/null 2>&1 || true
        sleep 3
    fi
    systemctl disable --now dhcpcd >/dev/null 2>&1 || warn "no se pudo detener dhcpcd"
    sleep 3

    # Verify the SSH path survived the handover.
    tries=0
    until ssh_path_alive; do
        tries=$((tries+1))
        [[ "${tries}" -ge 8 ]] && die "SSH (${SSH_IF}) sin IP tras retirar dhcpcd — restaurando"
        info "esperando que NM reasigne IP a ${SSH_IF}… (${tries}/8)"
        nmcli device connect "${SSH_IF}" >/dev/null 2>&1 || true
        sleep 2
    done
    ok "handover completado: NM gestiona ${SSH_IF}, enlace SSH intacto"
else
    ok "dhcpcd no estaba activo — sin handover necesario"
fi

# Stop other competing managers now that NM is firmly in control.
for svc in wpa_supplicant systemd-networkd; do
    systemctl disable --now "${svc}.service" >/dev/null 2>&1 || true
done
pkill -x wpa_supplicant 2>/dev/null || true

# ── 8. Final connectivity verification (real Internet) ───────────────────────
info "verificando Internet real…"
if has_internet "${SSH_IF}"; then
    ok "Internet real confirmado"
else
    warn "sin Internet real aún — NM puede tardar en reconectar; revisa wifi-status"
    # Not fatal for SSH (link is up); do not roll back solely on this.
fi

# ── 9. Detect antennas + default preference ──────────────────────────────────
usb="$(detect_iface usb)"; native="$(detect_iface native)"
printf 'usb\n' > "${WS_PREF_FILE}"
echo
info "antenas: usb=${usb:-none}  native=${native:-none}"

# ── 10. Install failover monitor (timer) — OFF by default ────────────────────
# We install the units but do NOT enable the timer automatically. The failover
# is opt-in: verify it behaves with `wifi-failover test`, then `wifi-failover on`.
info "instalando monitor de failover (desactivado por defecto)…"
cp -a "${SRC_DIR}/systemd/wifi-failover.service" /etc/systemd/system/
cp -a "${SRC_DIR}/systemd/wifi-failover.timer"   /etc/systemd/system/
systemctl daemon-reload
ok "failover instalado pero APAGADO — actívalo cuando quieras con: wifi-failover on"
echo "   (pruébalo antes sin riesgo con: wifi-failover test)"

# ── 11. SUCCESS: confirm commit, disarm rollback ─────────────────────────────
if ! ssh_path_alive; then
    die "verificación final: SSH caído — NO desarmo el rollback (se restaurará solo)"
fi
SAFE_DONE=1
disarm_rollback
trap - ERR

echo
ok "instalación de red completa y verificada — enlace SSH intacto"

# ── 12. Optional Tailscale (only INSTALL; user logs in later) ────────────────
echo
sep
if [[ "${Q_TS,,}" == "s" || "${Q_TS,,}" == "si" ]]; then
    if "${WS_BIN}/wifi-tailscale" install; then
        ok "Tailscale instalado y habilitado"
        echo "   inicia sesión tú mismo cuando quieras con:  sudo tailscale up --accept-dns=false"
    else
        warn "Tailscale no se completó — la red WiFi sigue OK. Reintenta: wifi-tailscale install"
    fi
else
    info "Tailscale omitido — instálalo luego con: wifi-tailscale install"
fi
sep
echo "Comandos: wifi-add wifi-saved wifi-list wifi-connect wifi-status"
echo "          wifi-prefer wifi-passwd wifi-showpass wifi-rm wifi-failover wifi-panic"
echo "          wifi-tailscale <setup|status>"
echo "wifi-connect <ssid>  ancla manual    |  wifi-connect --auto  vuelve a automático"
sep
echo "Failover: USB preferida → nativa, prueba Internet real cada 20s."
log INFO "install: OK (usb=${usb:-none} native=${native:-none} ssid=${ssid} ssh_if=${SSH_IF:-local})"
