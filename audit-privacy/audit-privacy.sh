#!/usr/bin/env bash
# audit-privacy — scan dirs for credentials, private IPs, MACs
# Compatible: Termux (no-root), Debian, Raspbian, macOS
# Usage: audit-privacy.sh [dir...]  (default: parent dir of script)

set -euo pipefail

# ── ANSI ──────────────────────────────────────────────────────────────────────
G='\033[0;32m'; Y='\033[0;33m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "${G}[OK]${N}  $*"; }
warn() { echo -e "${Y}[WARN]${N} $*"; }
err()  { echo -e "${R}[ERR]${N}  $*"; }
info() { echo -e "${C}[INFO]${N} $*"; }

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_ROOT="$(dirname "$SCRIPT_DIR")"

EXTENSIONS=("sh" "bash" "zsh" "env" "conf" "cfg" "ini" "json" "yaml" "yml"
            "toml" "md" "txt" "py" "rb" "js" "ts" "lua" "fish" "profile"
            "zshrc" "bashrc" "zshenv" "zprofile")

# Patterns: credentials
PAT_CREDS='password|passwd|secret|api_key|apikey|private_key|auth_key|bearer|access_key|token[_\.][a-z]|secret[_\.][a-z]'

# Patterns: private/RFC1918 IPs (flag these)
PAT_PRIV_IP='\b(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})\b'

# Patterns: public IPs (warn but lower severity)
PAT_PUB_IP='\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'

# Patterns: MAC addresses
PAT_MAC='[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}'

# Known-safe public IPs (skip)
SAFE_IPS='1\.1\.1\.1|8\.8\.8\.8|8\.8\.4\.4|9\.9\.9\.9|1\.0\.0\.1'

# Dirs to always skip
SKIP_DIRS=(".git" "node_modules" ".venv" "__pycache__" ".cache")

# ── Helpers ───────────────────────────────────────────────────────────────────
build_find_ext_args() {
    local args=()
    for i in "${!EXTENSIONS[@]}"; do
        [[ $i -gt 0 ]] && args+=("-o")
        args+=("-name" "*.${EXTENSIONS[$i]}")
    done
    # Also catch dotfiles with no extension (e.g. .zshrc)
    args+=("-o" "-name" ".*rc" "-o" "-name" ".*env" "-o" "-name" ".*profile")
    printf '%s\0' "${args[@]}"
}

build_prune_args() {
    local args=()
    for d in "${SKIP_DIRS[@]}"; do
        args+=("-name" "$d" "-prune" "-o")
    done
    printf '%s\0' "${args[@]}"
}

mask_line() {
    # Mask IPs and tokens in output; truncate at 100 chars
    echo "$1" \
        | sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/x.x.x.x/g' \
        | sed 's/[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}:[0-9a-fA-F]\{2\}/xx:xx:xx:xx:xx:xx/g' \
        | sed 's/\(.\{100\}\).*/\1…/'
}

scan_dir() {
    local target="$1"
    local proj
    proj="$(basename "$target")"
    local hits=0

    info "Scanning: $proj"

    # Build prune + extension find command portably
    local files
    files="$(
        find "$target" \
            \( -name ".git" -o -name "node_modules" -o -name ".venv" \
               -o -name "__pycache__" -o -name ".cache" \) -prune \
            -o -type f \( \
                -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \
                -o -name "*.env" -o -name "*.conf" -o -name "*.cfg" \
                -o -name "*.ini" -o -name "*.json" -o -name "*.yaml" \
                -o -name "*.yml" -o -name "*.toml" -o -name "*.md" \
                -o -name "*.txt" -o -name "*.py" -o -name "*.rb" \
                -o -name "*.js" -o -name "*.ts" -o -name "*.lua" \
                -o -name "*.fish" -o -name ".*rc" -o -name ".*env" \
                -o -name ".*profile" \
            \) -print 2>/dev/null
    )"

    [[ -z "$files" ]] && { ok "$proj — no files to scan"; return 0; }

    while IFS= read -r f; do
        # Credentials
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            hits=$((hits+1))
            err "CRED  $(mask_line "$line")"
        done < <(grep -inE "$PAT_CREDS" "$f" 2>/dev/null | grep -v '^\s*#\|^\s*-\|never\|not stored\|no credential\|reference only\|example\|sample\|startswith\|prompt\|PasswordAuthentication\|PermitEmptyPasswords\|PermitRootLogin\|wifi-passwd\|wifi-showpass\|getent passwd\|Keychain\|security.*password\|security.*generic\|read -r -s -p\|secrets_get\|secrets_delete\|add-generic\|find-generic\|delete-generic\|print_info\|print_error\|print_success\|print_warn' | grep -v ':[[:space:]]*#' || true)

        # Private IPs
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            hits=$((hits+1))
            err "PRIV-IP  $(mask_line "$line")"
        done < <(grep -nE "$PAT_PRIV_IP" "$f" 2>/dev/null | grep -v 'x\.x\.x\|127\.0\.0\.1\|example\|sample\|placeholder' | grep -v ':[[:space:]]*#' || true)

        # MACs
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            hits=$((hits+1))
            warn "MAC  $(mask_line "$line")"
        done < <(grep -nE "$PAT_MAC" "$f" 2>/dev/null | grep -v '^\s*#\|example\|sample\|formato\|format\|xx:xx\|AA:BB\|FF:FF' || true)

        # Public IPs (skip safe ones)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # skip private (already caught) and safe public
            echo "$line" | grep -qE "$PAT_PRIV_IP" && continue
            echo "$line" | grep -qE "$SAFE_IPS" && continue
            hits=$((hits+1))
            warn "PUB-IP  $(mask_line "$line")"
        done < <(grep -nE "$PAT_PUB_IP" "$f" 2>/dev/null | grep -v '^\s*#\|example\|sample\|ip route\|ip addr\|ifconfig\|x\.x\.x\|0\.0\.0\.0\|127\.0\.0\.1\|"version"\|1\.2\.3\.' | grep -v ':[[:space:]]*#' || true)

    done <<< "$files"

    if [[ $hits -eq 0 ]]; then
        ok "$proj — clean"
    else
        echo ""
    fi
    return $hits
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    local targets=()
    if [[ $# -gt 0 ]]; then
        for a in "$@"; do targets+=("$(realpath "$a")"); done
    else
        # Scan all first-level subdirs of parent (scripts/)
        while IFS= read -r d; do
            targets+=("$d")
        done < <(find "$DEFAULT_ROOT" -maxdepth 1 -mindepth 1 -type d \
                    ! -name ".git" ! -name "audit-privacy" | sort)
    fi

    local total_hits=0
    local clean=0
    local dirty=0

    echo ""
    info "audit-privacy — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "────────────────────────────────────────────────"

    for t in "${targets[@]}"; do
        scan_dir "$t"
        h=$?
        total_hits=$((total_hits + h))
        [[ $h -eq 0 ]] && clean=$((clean+1)) || dirty=$((dirty+1))
        echo ""
    done

    echo "────────────────────────────────────────────────"
    info "Done: ${clean} clean, ${dirty} need review, ${total_hits} total hits"
    echo ""
    [[ $total_hits -gt 0 ]] && exit 1 || exit 0
}

main "$@"
