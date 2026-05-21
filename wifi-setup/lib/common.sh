#!/usr/bin/env bash
# common.sh — shared library for wifi-setup tooling (NetworkManager-based)
# Sourced by every wifi-* binary and by install/uninstall.
# Not meant to be executed directly.

# ── Strict mode (only when executed, not when sourced into a strict parent) ──
set -Eeuo pipefail

# ── Paths ───────────────────────────────────────────────────────────────────
readonly WS_BASE="/opt/wifi-setup"
readonly WS_BIN="${WS_BASE}/bin"
readonly WS_LIB="${WS_BASE}/lib"
readonly WS_STATE="${WS_BASE}/state"
readonly WS_LOG_DIR="${WS_BASE}/logs"
readonly WS_LOG="${WS_LOG_DIR}/wifi-setup.log"

# Pin state: when present, holds the SSID the user locked manually.
readonly WS_PIN_FILE="${WS_STATE}/pinned"
# Preferred antenna: "usb" (default) or "native".
readonly WS_PREF_FILE="${WS_STATE}/preferred"

# ── Interface roles (resolved at runtime, never hardcoded) ──────────────────
# USB dongle is preferred by default; PCI is the native fallback.
# Detection is by bus type, robust against sysfs layout quirks.

# ── Connectivity test config ────────────────────────────────────────────────
# NM's own connectivity endpoint: tiny, fixed body, distinguishes
# "has IP route" from "has real Internet". Lower cost than pinging.
readonly WS_CHECK_URLS=(
    "http://nmcheck.gnome.org/check_network_status.txt"
    "http://connectivity-check.ubuntu.com"
)
readonly WS_CHECK_TIMEOUT=3   # seconds per probe; keeps 20s monitor cycle snappy

# ── Colored output ──────────────────────────────────────────────────────────
_c() { printf '\033[0;%sm%s\033[0m\n' "$1" "$2"; }
ok()   { _c 32 "✓ $*"; }
info() { _c 34 "→ $*"; }
warn() { _c 33 "! $*"; }
err()  { _c 31 "✗ $*" >&2; }
die()  { err "$*"; exit 1; }
sep()  { printf '────────────────────────────────────────\n'; }

# ── Logging (to file + stderr) ──────────────────────────────────────────────
log() {
    local level="$1"; shift
    local line
    line="[$(date '+%Y-%m-%dT%H:%M:%S%z')] [${level}] $*"
    if [[ -d "${WS_LOG_DIR}" ]]; then printf '%s\n' "${line}" >> "${WS_LOG}" 2>/dev/null || true; fi
    printf '%s\n' "${line}" >&2
}

# ── Guards ──────────────────────────────────────────────────────────────────
require_root() {
    [[ "${EUID}" -eq 0 ]] || die "debe ejecutarse como root (usa sudo)"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "comando requerido no encontrado: $1"
}

require_nm() {
    require_cmd nmcli
    systemctl is-active --quiet NetworkManager \
        || die "NetworkManager no está activo — ejecuta: systemctl start NetworkManager"
}

# ── Antenna detection ────────────────────────────────────────────────────────
# Echoes the interface name for a given role, or empty if absent.
# Role: "usb" | "native"
detect_iface() {
    local want="$1" dev bus syspath driver name
    for dev in /sys/class/net/*; do
        [[ -e "${dev}/wireless" || -e "${dev}/phy80211" ]] || continue
        syspath="$(readlink -f "${dev}/device" 2>/dev/null || true)"
        driver="$(basename "$(readlink -f "${dev}/device/driver" 2>/dev/null || echo '')" 2>/dev/null || true)"
        # Bus detection: prefer the device-symlink path, fall back to driver name.
        if printf '%s' "${syspath}" | grep -q '/usb'; then
            bus="usb"
        elif printf '%s' "${driver}" | grep -qiE 'u$|_usb|8821cu|8812au|rtl8.*u'; then
            bus="usb"   # Realtek USB dongles whose sysfs path hides the usb segment
        else
            bus="pci"
        fi
        name="$(basename "${dev}")"
        if [[ "${want}" == "usb" && "${bus}" == "usb" ]]; then
            printf '%s\n' "${name}"; return 0
        fi
        if [[ "${want}" == "native" && "${bus}" == "pci" ]]; then
            printf '%s\n' "${name}"; return 0
        fi
    done
    return 0   # not found: empty output, success (callers check for empty)
}

# Returns the role order to try, honoring the saved preference.
# Echoes two lines: first = preferred role, second = fallback role.
antenna_order() {
    local pref="usb"
    [[ -f "${WS_PREF_FILE}" ]] && pref="$(cat "${WS_PREF_FILE}")"
    if [[ "${pref}" == "native" ]]; then
        printf 'native\nusb\n'
    else
        printf 'usb\nnative\n'
    fi
}

# ── Pin state helpers ────────────────────────────────────────────────────────
pin_get()   { [[ -f "${WS_PIN_FILE}" ]] && cat "${WS_PIN_FILE}" || true; }
pin_set()   { mkdir -p "${WS_STATE}"; printf '%s\n' "$1" > "${WS_PIN_FILE}"; }
pin_clear() { rm -f "${WS_PIN_FILE}"; }

# ── Connectivity test ────────────────────────────────────────────────────────
# Returns 0 if real Internet is reachable through the given interface.
# Uses curl bound to the interface; falls back across URLs to avoid
# false negatives from a single dead endpoint.
has_internet() {
    # Note: we deliberately do NOT bind curl to an interface. Binding
    # (--interface) needs root AND gives false negatives right after a
    # reconnect or on tethered hotspots, which used to trigger reconnect
    # loops. A plain probe through the default route is the reliable signal.
    local url
    for url in "${WS_CHECK_URLS[@]}"; do
        if curl -fsS --max-time "${WS_CHECK_TIMEOUT}" -o /dev/null "${url}" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# ── NM helpers ────────────────────────────────────────────────────────────────
# All saved wifi profiles, one SSID per line.
nm_saved_ssids() {
    nmcli -t -f NAME,TYPE connection show 2>/dev/null \
        | awk -F: '$2 ~ /wireless/ {print $1}'
}

# Whether a profile with this name/SSID already exists.
nm_profile_exists() {
    nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$1"
}

# Bring an interface administratively down/up (failover toggle, no rfkill).
iface_down() { ip link set "$1" down 2>/dev/null && log INFO "iface down: $1" || true; }
iface_up()   { ip link set "$1" up   2>/dev/null && log INFO "iface up: $1"   || true; }

# Read a WPA passphrase twice (hidden), validate length and match.
# Echoes the validated password on stdout.
read_passphrase() {
    local p1 p2
    while true; do
        IFS= read -r -s -p "contraseña WPA (mín 8): " p1; echo >&2
        [[ "${#p1}" -ge 8 ]] || { err "mínimo 8 caracteres"; continue; }
        IFS= read -r -s -p "confirma la contraseña : " p2; echo >&2
        [[ "${p1}" == "${p2}" ]] || { err "no coinciden, reintenta"; continue; }
        printf '%s' "${p1}"
        return 0
    done
}

# ── SSH-safe commit/rollback ─────────────────────────────────────────────────
# When the installer runs over SSH, the link carrying our session must never
# be left without connectivity. We use a "confirmed commit" pattern: arm a
# system-level transient timer that restores the previous network state after
# a grace window; the installer cancels it only on success. If SSH drops, the
# timer is never cancelled and fires, restoring access.

readonly WS_SAFE_DIR="${WS_STATE}/safe"
readonly WS_ROLLBACK_UNIT="wifi-setup-rollback"
WS_GRACE_SEC="${WS_GRACE_SEC:-120}"   # confirmation window before auto-rollback

# Detect the interface that carries the current SSH session (empty if local).
ssh_iface() {
    [[ -n "${SSH_CONNECTION:-}" ]] || return 0
    local client_ip
    client_ip="$(printf '%s' "${SSH_CONNECTION}" | awk '{print $1}')"
    ip -o route get "${client_ip}" 2>/dev/null \
        | grep -oE 'dev [^ ]+' | awk '{print $2}' | head -1
}

# Snapshot the current working network so we can restore it verbatim.
snapshot_network() {
    mkdir -p "${WS_SAFE_DIR}"
    : > "${WS_SAFE_DIR}/restore.sh"
    {
        printf '#!/usr/bin/env bash\n# auto-generated network restore — DO NOT EDIT\nset +e\n'
        # Re-enable dhcpcd if it was the manager (most common pre-NM case).
        if systemctl is-enabled dhcpcd >/dev/null 2>&1 || systemctl is-active dhcpcd >/dev/null 2>&1; then
            printf 'systemctl restart dhcpcd 2>/dev/null\n'
        fi
        # Bring SSH interface back up and request a lease.
        local s; s="$(ssh_iface)"
        if [[ -n "${s}" ]]; then
            printf 'ip link set %s up 2>/dev/null\n' "${s}"
            printf 'command -v dhclient >/dev/null 2>&1 && dhclient -nw %s 2>/dev/null\n' "${s}"
            printf 'command -v dhcpcd  >/dev/null 2>&1 && dhcpcd %s 2>/dev/null\n' "${s}"
        fi
        printf 'logger -t wifi-setup "ROLLBACK ejecutado: red previa restaurada"\n'
    } >> "${WS_SAFE_DIR}/restore.sh"
    chmod +x "${WS_SAFE_DIR}/restore.sh"
    log INFO "snapshot de red guardado (ssh_iface=$(ssh_iface || echo local))"
}

# Arm the auto-rollback: fires after the grace window unless cancelled.
arm_rollback() {
    command -v systemd-run >/dev/null 2>&1 || { warn "systemd-run no disponible — sin red de seguridad"; return 0; }
    disarm_rollback   # ensure no stale unit
    systemd-run --system --unit="${WS_ROLLBACK_UNIT}" \
        --on-active="${WS_GRACE_SEC}" \
        --description="wifi-setup auto-rollback (SSH safety)" \
        "${WS_SAFE_DIR}/restore.sh" >/dev/null 2>&1 \
        && warn "ROLLBACK ARMADO: si pierdes conexión, la red previa se restaura en ${WS_GRACE_SEC}s" \
        || warn "no se pudo armar el rollback automático"
}

# Cancel the auto-rollback (called only after success is verified).
disarm_rollback() {
    systemctl stop "${WS_ROLLBACK_UNIT}.timer"   >/dev/null 2>&1 || true
    systemctl reset-failed "${WS_ROLLBACK_UNIT}.service" >/dev/null 2>&1 || true
}

# Verify connectivity through the SSH interface specifically (if over SSH).
# Returns 0 if the SSH path is still alive.
ssh_path_alive() {
    local s; s="$(ssh_iface)"
    [[ -z "${s}" ]] && return 0          # local session: nothing to protect
    # Interface must be administratively up AND have an IPv4 address.
    local operstate
    operstate="$(cat "/sys/class/net/${s}/operstate" 2>/dev/null || echo down)"
    [[ "${operstate}" == "up" || "${operstate}" == "unknown" ]] || return 1
    ip -4 addr show "${s}" 2>/dev/null | grep -q 'inet ' || return 1
    return 0
}

# ── Tailscale (optional final phase) ─────────────────────────────────────────
# Login via browser (default) or a one-shot auth key pasted interactively.
# Target config for this host: simple node + Tailscale SSH, no MagicDNS:
#   tailscale up --ssh --accept-dns=false
# An auth key, if used, is read into a local var, exported to the child only,
# never written to disk, never logged, never visible in `ps`.

ts_installed() { command -v tailscale >/dev/null 2>&1; }

ts_connected() {
    ts_installed || return 1
    tailscale status >/dev/null 2>&1 || return 1
    ip -o addr show tailscale0 2>/dev/null | grep -q 'inet '
}

# Install via the official installer (auto-detects amd64/arm64/armhf).
ts_install() {
    require_cmd curl
    info "instalando Tailscale (detecta ARM/x64 automáticamente)…"
    curl -fsSL https://tailscale.com/install.sh | sh \
        || die "fallo instalando Tailscale"
    systemctl enable --now tailscaled >/dev/null 2>&1 \
        || die "no se pudo habilitar tailscaled"
    ts_installed || die "tailscale no quedó instalado"
    ok "Tailscale instalado ($(tailscale version 2>/dev/null | head -1))"
}

# Upgrade in place if the official apt repo offers a newer version.
ts_maybe_upgrade() {
    info "comprobando actualizaciones de Tailscale…"
    apt-get update -qq >/dev/null 2>&1 || true
    if apt-get install -y --only-upgrade tailscale >/dev/null 2>&1; then
        ok "Tailscale al día ($(tailscale version 2>/dev/null | head -1))"
    else
        warn "no se pudo actualizar vía apt (¿instalado por otro método?)"
    fi
}
