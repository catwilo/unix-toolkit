#!/usr/bin/env bash
# aicli setup.sh — installs host dependencies, creates directories, configures byobu
set -euo pipefail

AICLI_DATA="${HOME}/.local/share/aicli"
AICLI_CFG="${HOME}/.config/aicli"
IPC_DIR="/tmp/aicli"
QUADLET_DIR="${HOME}/.config/containers/systemd"
BIN_DIR="${HOME}/.local/bin"

# ── Colours ───────────────────────────────────────────────────────────────────
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }

# ── Detect distro ─────────────────────────────────────────────────────────────
detect_distro() {
  if   command -v dnf  &>/dev/null; then echo "fedora"
  elif command -v apt  &>/dev/null; then echo "debian"
  elif command -v pacman &>/dev/null; then echo "arch"
  else echo "unknown"; fi
}

DISTRO="$(detect_distro)"

pkg_install() {
  case "$DISTRO" in
    fedora) sudo dnf install -y "$@" ;;
    debian) sudo apt-get install -y "$@" ;;
    arch)   sudo pacman -S --noconfirm "$@" ;;
    *)      red "Cannot auto-install on this distro. Install manually: $*"; exit 1 ;;
  esac
}

# Map tool → package name per distro
install_if_missing() {
  local cmd="$1" pkg_fed="$2" pkg_deb="$3" pkg_arch="$4"
  if command -v "$cmd" &>/dev/null; then
    green "  ✓ $cmd"
  else
    yellow "  installing $cmd..."
    case "$DISTRO" in
      fedora) sudo dnf install -y "$pkg_fed" ;;
      debian) sudo apt-get install -y "$pkg_deb" ;;
      arch)   sudo pacman -S --noconfirm "$pkg_arch" ;;
    esac
    green "  ✓ $cmd installed"
  fi
}

# ── Required deps ─────────────────────────────────────────────────────────────
green "→ Installing required dependencies..."

# Ensure apt index is fresh on Debian/Ubuntu (only once)
[[ "$DISTRO" == "debian" ]] && sudo apt-get update -qq

install_if_missing podman   podman          podman          podman
install_if_missing byobu    byobu           byobu           byobu
install_if_missing go       golang          golang-go       go
install_if_missing socat    socat           socat           socat   # byobu-status.sh uses it

# ── Optional deps ─────────────────────────────────────────────────────────────
green "→ Installing optional dependencies..."
install_if_missing glow     "" "" ""  || true   # not in standard repos — install via Go below
install_if_missing age      age             age             age

# glow: install via `go install` if not found and Go is available
if ! command -v glow &>/dev/null && command -v go &>/dev/null; then
  yellow "  installing glow via go install..."
  GOBIN="${HOME}/.local/bin" go install github.com/charmbracelet/glow@latest 2>/dev/null \
    && green "  ✓ glow installed" \
    || yellow "  ⚠  glow install failed — markdown will render as plain text"
fi

# ── Directory setup ───────────────────────────────────────────────────────────
green "→ Creating data directories..."
mkdir -p \
  "${AICLI_DATA}/profiles" \
  "${AICLI_DATA}/memory" \
  "${AICLI_DATA}/snapshots" \
  "${AICLI_DATA}/history" \
  "${AICLI_DATA}/logs" \
  "${AICLI_CFG}/prompts" \
  "${IPC_DIR}" \
  "${BIN_DIR}"

chmod 700 "${AICLI_DATA}/profiles" "${IPC_DIR}"

# ── Config ────────────────────────────────────────────────────────────────────
if [[ ! -f "${AICLI_CFG}/config.yaml" ]]; then
  green "→ Installing default config..."
  cp "$(dirname "$0")/../config/config.example.yaml" "${AICLI_CFG}/config.yaml"
  yellow "  Edit ${AICLI_CFG}/config.yaml to add your accounts"
else
  green "  ✓ config.yaml already exists"
fi

# ── Build container images ────────────────────────────────────────────────────
green "→ Building container images..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

build_image() {
  local name="$1" ctx="$2"
  green "  Building ${name}..."
  podman build -t "localhost/${name}:latest" -f "${ctx}/Containerfile" "${ctx}"
}

build_image aicli-sentinel       "${REPO_ROOT}/containers/sentinel"
build_image aicli-orchestrator   "${REPO_ROOT}/containers/orchestrator"
build_image aicli-memory-engine  "${REPO_ROOT}/containers/memory-engine"
build_image aicli-compressor     "${REPO_ROOT}/containers/compressor"
build_image aicli-browser-worker "${REPO_ROOT}/containers/browser-worker"

# ── Build CLI binary ──────────────────────────────────────────────────────────
green "→ Building aicli CLI binary..."
(cd "${REPO_ROOT}/cli" && CGO_ENABLED=0 go build -ldflags="-s -w" -o "${BIN_DIR}/aicli" ./cmd/aicli)
green "  ✓ ${BIN_DIR}/aicli installed"

# ── Quadlets ──────────────────────────────────────────────────────────────────
green "→ Installing systemd quadlets..."
mkdir -p "${QUADLET_DIR}"
cp "${REPO_ROOT}/podman/quadlets/"* "${QUADLET_DIR}/"
systemctl --user daemon-reload
green "  ✓ Quadlets installed"

# ── Byobu integration ─────────────────────────────────────────────────────────
green "→ Configuring byobu..."
BYOBU_STATUS_DIR="${HOME}/.config/byobu"
mkdir -p "${BYOBU_STATUS_DIR}"

# Add aicli status plugin if not already present
STATUS_PLUGIN="${BYOBU_STATUS_DIR}/aicli_status.sh"
if [[ ! -f "${STATUS_PLUGIN}" ]]; then
  cp "${REPO_ROOT}/scripts/byobu-status.sh" "${STATUS_PLUGIN}"
  chmod +x "${STATUS_PLUGIN}"
  green "  ✓ Byobu status plugin installed"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
green "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
green " aicli setup complete!"
green "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Edit ~/.config/aicli/config.yaml with your accounts"
echo "  2. Start the pod:"
echo "     systemctl --user enable --now aicli-pod"
echo "  3. Login to your accounts:"
echo "     aicli session new --account personal-1 --ai claude"
echo "  4. Send your first message:"
echo "     aicli send 'hello!'"
echo ""
