#!/usr/bin/env bash
set -euo pipefail

# ---- CONSTANTS ----------------------------------------------------------
GITHUB_USER="catwilo"
UT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ut"
LOCAL_BIN="$HOME/.local/bin"
SSH_KEY="$HOME/.ssh/id_ed25519"

GIT_NAME=""
GIT_EMAIL=""
GIT_USER=""
SKIP_VERIFY=0

# ---- LOGGING --------------------------------------------------------------
G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; B=$'\033[1m'; Z=$'\033[0m'
ok()   { printf "%s[OK]%s %s\n" "$G" "$Z" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$Y" "$Z" "$*"; }
err()  { printf "%s[ERROR]%s %s\n" "$R" "$Z" "$*" >&2; }
info() { printf "%s[INFO]%s %s\n" "$C" "$Z" "$*"; }
step() { printf "%s== %s ==%s\n" "$B" "$*" "$Z"; }
die()  { err "$*"; exit 1; }

# ---- PHASE 0: INTAKE -------------------------------------------------------
phase0_intake() {
    step "PHASE 0: INTAKE"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --git-name)   GIT_NAME="$2"; shift 2 ;;
            --git-email)  GIT_EMAIL="$2"; shift 2 ;;
            --git-user)   GIT_USER="$2"; shift 2 ;;
            --skip-verify) SKIP_VERIFY=1; shift ;;
            *) die "unknown flag: $1" ;;
        esac
    done

    if [ -z "$GIT_NAME" ]; then
        printf "git user.name: "
        read -r GIT_NAME
    fi
    if [ -z "$GIT_EMAIL" ]; then
        printf "git user.email: "
        read -r GIT_EMAIL
    fi
    if [ -z "$GIT_USER" ]; then
        GIT_USER="$GITHUB_USER"
    fi

    [ -n "$GIT_NAME" ]  || die "git-name required"
    [ -n "$GIT_EMAIL" ] || die "git-email required"

    ok "intake complete: name=$GIT_NAME email=$GIT_EMAIL user=$GIT_USER"
}

# ---- PHASE 1: DETECT --------------------------------------------------------
PLATFORM=""
ARCH=""
PKG_MGR=""

phase1_detect() {
    step "PHASE 1: DETECT"
    ARCH="$(uname -m)"

    if [ -d "/data/data/com.termux" ]; then
        PLATFORM="termux"
        PKG_MGR="pkg"
    elif [ -f "/etc/debian_version" ]; then
        PLATFORM="debian"
        PKG_MGR="apt"
    elif [ "$(uname -s)" = "Darwin" ]; then
        PLATFORM="mac"
        PKG_MGR="brew"
    else
        PLATFORM="unknown"
        PKG_MGR="none"
        warn "platform not recognized -- proceeding generically"
    fi

    export PLATFORM ARCH PKG_MGR
    ok "detected: platform=$PLATFORM arch=$ARCH pkg_mgr=$PKG_MGR"
}

# ---- PHASE 2: CONFIGURE -----------------------------------------------------
phase2_configure() {
    step "PHASE 2: CONFIGURE"

    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    git config --global push.followTags true
    git config --global pull.rebase true
    git config --global core.editor "${EDITOR:-nvim}"
    ok "git global config applied"

    if [ -f "$SSH_KEY" ]; then
        ok "SSH key already exists: $SSH_KEY"
    else
        info "generating SSH key..."
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "$GIT_EMAIL"
        ok "SSH key generated: $SSH_KEY"
    fi

    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            ok "gh already authenticated"
        else
            warn "gh not authenticated -- run: gh auth login"
        fi
    else
        warn "gh CLI not found -- install it for full functionality"
    fi
}

# ---- PHASE 3: SYMLINK --------------------------------------------------------
phase3_symlink() {
    step "PHASE 3: SYMLINK"

    [ -f "$UT_SRC" ] || die "ut not found at $UT_SRC"

    mkdir -p "$LOCAL_BIN"
    ln -sf "$UT_SRC" "$LOCAL_BIN/ut"
    ok "symlinked: $LOCAL_BIN/ut -> $UT_SRC"

    case ":$PATH:" in
        *":$LOCAL_BIN:"*) ok "$LOCAL_BIN already in PATH" ;;
        *) warn "$LOCAL_BIN not in PATH -- add it to your shell rc file" ;;
    esac
}

# ---- PHASE 4: VERIFY ----------------------------------------------------------
declare -a VERIFY_RESULTS=()

phase4_verify() {
    step "PHASE 4: VERIFY"

    if [ "$SKIP_VERIFY" -eq 1 ]; then
        warn "verify skipped (--skip-verify)"
        VERIFY_RESULTS+=("VERIFY|SKIPPED|--skip-verify flag set")
        return
    fi

    local _email
    _email="$(git config --global user.email 2>/dev/null || true)"
    if [ "$_email" = "$GIT_EMAIL" ]; then
        VERIFY_RESULTS+=("GIT-EMAIL|OK|$_email")
    else
        VERIFY_RESULTS+=("GIT-EMAIL|FAIL|expected $GIT_EMAIL got $_email")
    fi

    if [ -f "$SSH_KEY" ]; then
        local _fp
        _fp="$(ssh-keygen -lf "$SSH_KEY" 2>/dev/null | awk '{print $2}')"
        VERIFY_RESULTS+=("SSH-KEY|OK|$_fp")
    else
        VERIFY_RESULTS+=("SSH-KEY|FAIL|key not found")
    fi

    if command -v ut >/dev/null 2>&1; then
        VERIFY_RESULTS+=("UT-CMD|OK|$(command -v ut)")
    else
        VERIFY_RESULTS+=("UT-CMD|FAIL|ut not found in PATH")
    fi

    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        VERIFY_RESULTS+=("GH-AUTH|OK|authenticated")
    else
        VERIFY_RESULTS+=("GH-AUTH|INFO|not authenticated or gh missing")
    fi
}

# ---- SUMMARY ----------------------------------------------------------------
print_summary() {
    step "SUMMARY"
    local _failed=0
    printf "%-12s %-10s %s\n" "PHASE" "STATUS" "NOTE"
    for _line in "${VERIFY_RESULTS[@]}"; do
        IFS='|' read -r _name _status _note <<< "$_line"
        case "$_status" in
            OK)      printf "%-12s %s%-10s%s %s\n" "$_name" "$G" "$_status" "$Z" "$_note" ;;
            FAIL)    printf "%-12s %s%-10s%s %s\n" "$_name" "$R" "$_status" "$Z" "$_note"; _failed=1 ;;
            SKIPPED) printf "%-12s %s%-10s%s %s\n" "$_name" "$Y" "$_status" "$Z" "$_note" ;;
            *)       printf "%-12s %s%-10s%s %s\n" "$_name" "$C" "$_status" "$Z" "$_note" ;;
        esac
    done
    if [ "$_failed" -eq 1 ]; then
        err "setup completed with failures"
        exit 1
    else
        ok "setup completed successfully"
        exit 0
    fi
}

# ---- MAIN ---------------------------------------------------------------------
phase0_intake "$@"
phase1_detect
phase2_configure
phase3_symlink
phase4_verify
print_summary
