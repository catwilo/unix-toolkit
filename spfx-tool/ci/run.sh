#!/usr/bin/env bash
# ci/run.sh — CI pipeline: static analysis + environment verify + smoke tests.
# Designed to run non-interactively; exits non-zero on any failure.
# Usage: ci/run.sh [--lint-only] [--no-tests]
# shellcheck shell=bash
set -euo pipefail

export SPFX_DIR="${SPFX_DIR:-$HOME/dev/spfx}"
export LOG_FILE="${SPFX_DIR}/logs/ci-$(date '+%Y%m%d-%H%M%S').log"
export NO_COLOR="${NO_COLOR:-}"  # Respect CI color preference

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/core.sh
source "${_SCRIPT_DIR}/lib/core.sh"

_LINT_ONLY=0
_NO_TESTS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lint-only) _LINT_ONLY=1; shift ;;
        --no-tests)  _NO_TESTS=1;  shift ;;
        *) log_die "Unknown option: $1" ;;
    esac
done

_CI_FAIL=0

# ── Phase 1: Static analysis ──────────────────────────────────────────────────
log_step "Phase 1 · Static analysis"

# shellcheck
if command -v shellcheck >/dev/null 2>&1; then
    log_info "shellcheck..."
    if shellcheck \
        --shell=bash \
        --severity=warning \
        --exclude=SC1091 \
        "${_SCRIPT_DIR}/bin"/spfx-* \
        "${_SCRIPT_DIR}/lib"/*.sh \
        "${_SCRIPT_DIR}/ci/run.sh" >> "${LOG_FILE}" 2>&1; then
        log_ok "shellcheck: passed"
    else
        log_warn "shellcheck: warnings/errors — see log"
        ((_CI_FAIL++)) || true
    fi
else
    log_warn "shellcheck not installed — skipping (install: apt-get install shellcheck)"
fi

# shfmt
if command -v shfmt >/dev/null 2>&1; then
    log_info "shfmt..."
    if shfmt -d -i 4 -ln bash \
        "${_SCRIPT_DIR}/bin"/spfx-* \
        "${_SCRIPT_DIR}/lib"/*.sh >> "${LOG_FILE}" 2>&1; then
        log_ok "shfmt: no formatting issues"
    else
        log_warn "shfmt: formatting issues found"
        ((_CI_FAIL++)) || true
    fi
else
    log_warn "shfmt not installed — skipping"
fi

# bash -n (syntax check — always available)
log_info "bash -n (syntax)..."
_syntax_fail=0
for _f in "${_SCRIPT_DIR}/bin"/spfx-* "${_SCRIPT_DIR}/lib"/*.sh; do
    bash -n "$_f" 2>> "${LOG_FILE}" || { log_warn "Syntax error: $_f"; _syntax_fail=1; }
done
if [[ "$_syntax_fail" -eq 0 ]]; then
    log_ok "bash -n: all files syntactically valid"
else
    ((_CI_FAIL++)) || true
fi

if [[ "$_LINT_ONLY" -eq 1 ]]; then echo ""; log_info "Lint-only mode — stopping here."; [[ "$_CI_FAIL" -eq 0 ]]; fi

# ── Phase 2: Environment verification ────────────────────────────────────────
log_step "Phase 2 · Environment"
if "${_SCRIPT_DIR}/bin/spfx-verify" --quiet >> "${LOG_FILE}" 2>&1; then
    log_ok "Environment: OK"
else
    log_warn "Environment: verification failed"
    ((_CI_FAIL++)) || true
fi

# ── Phase 3: Smoke tests ──────────────────────────────────────────────────────
if [[ "$_NO_TESTS" -eq 0 ]]; then
    log_step "Phase 3 · Smoke tests"
    if "${_SCRIPT_DIR}/bin/spfx-test" --fixture all >> "${LOG_FILE}" 2>&1; then
        log_ok "Smoke tests: all passed"
    else
        log_warn "Smoke tests: failures detected"
        ((_CI_FAIL++)) || true
    fi
fi

# ── CI Summary ────────────────────────────────────────────────────────────────
echo ""
if [[ "$_CI_FAIL" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  CI PASSED${NC}"
else
    echo -e "${RED}${BOLD}  CI FAILED — ${_CI_FAIL} stage(s) failed${NC}"
fi
echo -e "  Log: ${DIM}${LOG_FILE}${NC}"
echo ""

[[ "$_CI_FAIL" -eq 0 ]]
