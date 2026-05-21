#!/usr/bin/env bash
# setup.sh — Entry point. Copies files, removes stale image, runs bootstrap.
# Usage: bash setup.sh [--skip-verify] [-v] [-vvv] [--yes]
# shellcheck shell=bash
set -euo pipefail

SPFX_DIR="${SPFX_DIR:-$HOME/dev/spfx}"
_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors (only when stdout is a terminal) ───────────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    _G='\033[0;32m'; _Y='\033[1;33m'; _C='\033[0;36m'
    _B='\033[1m';    _D='\033[2m';    _R='\033[0;31m'; _N='\033[0m'
else
    _G=''; _Y=''; _C=''; _B=''; _D=''; _R=''; _N=''
fi

_ok()   { echo -e "${_G}  ✔${_N}  $*"; }
_info() { echo -e "${_C}  →${_N}  $*"; }
_warn() { echo -e "${_Y}  ⚠${_N}  $*"; }
_head() { echo -e "\n${_B}${_C}══ $* ${_N}${_D}$(printf '═%.0s' {1..40})${_N}"; }

# ── Flags ─────────────────────────────────────────────────────────────────────
_YES=0       # --yes  → skip all prompts, keep existing
_PASS_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y) _YES=1; shift ;;
        *)        _PASS_ARGS+=("$1"); shift ;;
    esac
done

# ── Detect what already exists ────────────────────────────────────────────────
_has_files=0
_has_image=0
_has_containers=0

[[ -d "${SPFX_DIR}/bin" && -d "${SPFX_DIR}/lib" ]] && _has_files=1

if command -v podman >/dev/null 2>&1; then
    podman image exists "localhost/spfx-dev:latest" 2>/dev/null && _has_image=1
    [[ -n "$(podman ps -q 2>/dev/null || true)" ]]             && _has_containers=1
fi

# ── Interactive overwrite prompt (skipped with --yes or when nothing exists) ──
_overwrite_files=0
_overwrite_image=0

if [[ "$_YES" -eq 1 || ( "$_has_files" -eq 0 && "$_has_image" -eq 0 ) ]]; then
    # Nothing to ask: fresh install, or caller said --yes (keep everything as-is)
    :
else
    _head "Existing installation detected at ${SPFX_DIR}"
    echo ""

    if [[ "$_has_files" -eq 1 ]]; then
        echo -e "  ${_Y}[1]${_N} Scripts & config  ${_D}(bin/ lib/ fixtures/ versions.env)${_N}"
    fi
    if [[ "$_has_image" -eq 1 ]]; then
        echo -e "  ${_Y}[2]${_N} Container image   ${_D}(localhost/spfx-dev:latest)${_N}"
    fi
    echo ""
    echo -e "  ${_D}Overwrite nothing to keep your current environment intact.${_N}"
    echo -e "  ${_D}Note: the image bakes a warmed npm cache and lockfiles derived from${_N}"
    echo -e "  ${_D}the fixtures, so overwriting files also rebuilds the image to stay${_N}"
    echo -e "  ${_D}consistent (a stale image would break npm ci --prefer-offline).${_N}"
    echo ""

    # Build the prompt dynamically based on what exists
    _choices="s"   # s = skip (always available)
    _prompt="  Overwrite → "
    _opts=()

    if [[ "$_has_files" -eq 1 && "$_has_image" -eq 1 ]]; then
        _prompt+="[f]iles+image  [i]mage only  [s]kip: "
        _choices="fis"
    elif [[ "$_has_files" -eq 1 ]]; then
        _prompt+="[f]iles  [s]kip: "
        _choices="fs"
    elif [[ "$_has_image" -eq 1 ]]; then
        _prompt+="[i]mage  [s]kip: "
        _choices="is"
    fi

    while true; do
        read -rp "$(echo -e "${_prompt}")" _choice
        _choice="${_choice,,}"   # lowercase
        case "$_choice" in
            # Files are the source of truth for the image's warmed cache and
            # baked lockfiles; overwriting files therefore forces an image
            # rebuild so `npm ci --prefer-offline` stays deterministic.
            f) [[ "$_choices" == *f* ]] && { _overwrite_files=1; _overwrite_image=1; break; } ;;
            i) [[ "$_choices" == *i* ]] && { _overwrite_image=1; break; } ;;
            b) [[ "$_choices" == *f* ]] && { _overwrite_files=1; _overwrite_image=1; break; } ;;
            s|"") break ;;   # empty Enter = skip
        esac
        _warn "Invalid choice — enter one of: $(echo "$_choices" | grep -o . | tr '\n' '/' | sed 's|/$||')"
    done
    echo ""
fi

# ── Fresh install always copies everything ────────────────────────────────────
[[ "$_has_files" -eq 0 ]] && _overwrite_files=1
[[ "$_has_image" -eq 0 ]] && _overwrite_image=1

# ── Copy files ────────────────────────────────────────────────────────────────
if [[ "$_overwrite_files" -eq 1 ]]; then
    _info "Copying spfx-tool to ${SPFX_DIR}..."
    mkdir -p "${SPFX_DIR}"
    cp -r "${_SOURCE_DIR}/bin"          "${SPFX_DIR}/"
    cp -r "${_SOURCE_DIR}/lib"          "${SPFX_DIR}/"
    cp -r "${_SOURCE_DIR}/ci"           "${SPFX_DIR}/"
    cp -r "${_SOURCE_DIR}/fixtures"     "${SPFX_DIR}/"
    cp    "${_SOURCE_DIR}/versions.env" "${SPFX_DIR}/"
    chmod 0755 "${SPFX_DIR}/bin"/spfx-*
    chmod 0755 "${SPFX_DIR}/ci/run.sh"
    _ok "Files updated"
else
    _ok "Files unchanged (skipped)"
fi

# ── Container image ───────────────────────────────────────────────────────────
if [[ "$_overwrite_image" -eq 1 ]] && command -v podman >/dev/null 2>&1; then
    if [[ "$_has_containers" -eq 1 ]]; then
        _info "Stopping running containers..."
        podman ps -q | xargs -r podman kill 2>/dev/null || true
        sleep 1
    fi
    if [[ "$_has_image" -eq 1 ]]; then
        _info "Removing stale image (localhost/spfx-dev:latest)..."
        podman image rm "localhost/spfx-dev:latest" 2>/dev/null || true
        _ok "Stale image removed — bootstrap will rebuild"
    fi
else
    if [[ "$_has_image" -eq 1 ]]; then
        _ok "Image unchanged (skipped) — bootstrap will reuse it"
    fi
fi

export SPFX_DIR
exec "${SPFX_DIR}/bin/spfx-bootstrap" "${_PASS_ARGS[@]}"
