#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load core first, then modules ─────────────────────────────────────────────
source "$HERE/lib/core.sh"
source "$HERE/lib/detect.sh"
source "$HERE/lib/pkg.sh"
source "$HERE/lib/links.sh"
source "$HERE/lib/plugins.sh"
source "$HERE/lib/mpd.sh"

# ── Config ────────────────────────────────────────────────────────────────────
CUSTOM_TERMUX_REPO="${CUSTOM_TERMUX_REPO:-https://github.com/catwilo/custom_termux.git}"
CUSTOM_TERMUX_DIR="${CUSTOM_TERMUX_DIR:-$HOME/custom_termux}"

# ── Arg parsing ───────────────────────────────────────────────────────────────
ONLY=""
for arg in "$@"; do
  case "$arg" in
    --only=*)   ONLY="${arg#--only=}" ;;
    --dry-run)  DRY_RUN=1 ;;
    --help|-h)
      echo "Uso: setup.sh [--only=pkg|links|mpd] [--dry-run]"
      exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

# ── Stages ────────────────────────────────────────────────────────────────────
stage_platform() {
  init_platform
}

stage_clone() {
  step "Repositorio custom_termux"
  if [ -d "$CUSTOM_TERMUX_DIR/.git" ]; then
    info "Ya existe — omitiendo clone"
  else
    require_cmd git
    run git clone "$CUSTOM_TERMUX_REPO" "$CUSTOM_TERMUX_DIR"
    ok "Clonado en $CUSTOM_TERMUX_DIR"
  fi
}

stage_pkg() {
  step "Instalando paquetes"
  local env_file="$HERE/packages/${PLATFORM}.env"
  require_file "$env_file"
  pkg_install_file "$env_file"

  # starship: no apt package on debian
  if [ "$PLATFORM" = "debian" ] && ! command -v starship >/dev/null 2>&1; then
    info "Instalando starship via script oficial..."
    run curl -sS https://starship.rs/install.sh | run sh -s -- -y
  fi
}

stage_links() {
  link_dotfiles
  verify_plugins
}

stage_mpd() {
  setup_mpd
}

stage_shell() {
  step "Shell por defecto"
  local zsh_bin; zsh_bin="$(command -v zsh)"
  if [ "$SHELL" = "$zsh_bin" ]; then
    info "zsh ya es el shell activo"
  else
    case "$PLATFORM" in
      termux) run chsh -s zsh ;;
      debian) run chsh -s "$zsh_bin" ;;
    esac
    ok "Shell cambiado a zsh — reinicia la terminal"
  fi
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
stage_platform

case "${ONLY}" in
  pkg)   stage_pkg   ;;
  links) stage_clone; stage_links ;;
  mpd)   stage_mpd   ;;
  "")
    stage_clone
    stage_pkg
    stage_links
    stage_mpd
    stage_shell
    printf "\n${G}${B}  Setup completo.${Z}\n"
    ;;
  *) die "Valor inválido para --only: $ONLY" ;;
esac
