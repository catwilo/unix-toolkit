#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$HERE/lib/core.sh"
source "$HERE/lib/detect.sh"
source "$HERE/lib/pkg.sh"
source "$HERE/lib/links.sh"
source "$HERE/lib/plugins.sh"
source "$HERE/lib/mpd.sh"

CUSTOM_TERMUX_REPO="${CUSTOM_TERMUX_REPO:-https://github.com/catwilo/custom_termux.git}"
CUSTOM_TERMUX_DIR="${CUSTOM_TERMUX_DIR:-$HOME/custom_termux}"
NVIM_SETUP="$HERE/../nvim-setup/setup.sh"

usage() {
  printf "%s\n" \
    "Uso: setup.sh [opciones]" \
    "" \
    "  --all          Instala todo: core + nvim + mpd" \
    "  --only=STAGE   Stage: pkg | links | nvim | mpd" \
    "  --dry-run      Simula sin ejecutar cambios" \
    "  --help, -h     Muestra esta ayuda" \
    "" \
    "Stages core (siempre en instalacion completa):" \
    "  pkg            Instala paquetes" \
    "  links          Clona dotfiles y enlaza a HOME" \
    "  shell          Establece zsh como shell" \
    "" \
    "Stages opcionales:" \
    "  nvim           LSP servers y plugins neovim" \
    "  mpd            MPD (Termux: PulseAudio / Debian: ALSA)" \
    "" \
    "Variables de entorno:" \
    "  CUSTOM_TERMUX_REPO  URL repo dotfiles" \
    "  CUSTOM_TERMUX_DIR   Directorio destino clone" \
    "  DRY_RUN=1           Equivalente a --dry-run"
  exit 0
}

ONLY=""
OPT_ALL=0
for arg in "$@"; do
  case "$arg" in
    --all)      OPT_ALL=1 ;;
    --only=*)   ONLY="${arg#--only=}" ;;
    --dry-run)  DRY_RUN=1 ;;
    --help|-h)  usage ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

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
  pkg_install_file "$HERE/packages/${PLATFORM}.env"
  if [ "$PLATFORM" = "debian" ] && ! command -v starship >/dev/null 2>&1; then
    info "Instalando starship..."
    run curl -sS https://starship.rs/install.sh | run sh -s -- -y
  fi
}

stage_links() {
  stage_clone
  link_dotfiles
  verify_plugins
}

stage_nvim() {
  step "Setup neovim"
  if [ ! -f "$NVIM_SETUP" ]; then
    warn "nvim-setup no encontrado en $NVIM_SETUP — omitiendo"
    return 0
  fi
  run bash "$NVIM_SETUP"
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

stage_core() {
  stage_pkg
  stage_links
  stage_shell
}

init_platform

case "${ONLY}" in
  pkg)   stage_pkg ;;
  links) stage_links ;;
  nvim)  stage_nvim ;;
  mpd)   setup_mpd ;;
  "")
    stage_core
    if [ "$OPT_ALL" = "1" ]; then
      stage_nvim
      setup_mpd
    fi
    printf "\n  Setup completo.\n"
    ;;
  *) die "Stage invalido: $ONLY" ;;
esac
