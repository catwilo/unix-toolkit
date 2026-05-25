# detect.sh — platform and package manager detection
# Requires: core.sh

# ── Platform ──────────────────────────────────────────────────────────────────
detect_platform() {
  if [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ]; then
    echo "termux"
  elif [ -f "/etc/debian_version" ]; then
    echo "debian"
  elif [ "$(uname)" = "Darwin" ]; then
    echo "macos"
  else
    echo "unknown"
  fi
}

# ── Package manager ───────────────────────────────────────────────────────────
detect_pkgmgr() {
  case "$(detect_platform)" in
    termux)  echo "pkg"  ;;
    debian)  echo "apt"  ;;
    macos)   echo "nix"  ;;  # stub: nix not yet implemented
    *)       echo "unknown" ;;
  esac
}

# ── Export globals (called once from setup.sh) ────────────────────────────────
init_platform() {
  PLATFORM="$(detect_platform)"
  PKGMGR="$(detect_pkgmgr)"
  [ "$PLATFORM" = "unknown" ] && die "Plataforma no soportada"
  [ "$PLATFORM" = "macos"   ] && die "macOS (nix) aún no implementado"
  info "Plataforma: $PLATFORM | Gestor: $PKGMGR"
}
