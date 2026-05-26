#!/bin/sh
# ut-setup.sh — first-run cold bootstrap; clones all catwilo repos into ~/unix-toolkit-tools
# Safe to re-run: pulls existing, clones missing.
# Requires: gh (authenticated), git
set -eu
G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'; Z='\033[0m'
ok()   { printf "${G}✓ %s${Z}\n" "$*"; }
warn() { printf "${Y}⚠ %s${Z}\n" "$*"; }
err()  { printf "${R}✗ %s${Z}\n" "$*" >&2; }
info() { printf "${C}→ %s${Z}\n" "$*"; }

GITHUB_USER="catwilo"
INDEX_REPO="unix-toolkit"
DST="${UNIX_TOOLKIT_TOOLS:-$HOME/unix-toolkit-tools}"

gh auth status >/dev/null 2>&1 || { err "gh not authenticated — run: gh auth login"; exit 1; }

mkdir -p "$DST"
info "fetching repo list for $GITHUB_USER → $DST"

SELF="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.local/bin"
ln -sf "$SELF/ut" "$HOME/.local/bin/ut" && ok "ut symlink → ~/.local/bin/ut"

errors=0
gh repo list "$GITHUB_USER" --limit 100 --json name --jq '.[].name' \
| grep -v "^${INDEX_REPO}$" \
| while IFS= read -r repo; do
    target="$DST/$repo"
    if [ -d "$target/.git" ]; then
        warn "$repo — updating..."
        git -C "$target" pull --rebase --autostash 2>/dev/null \
            && ok "$repo updated" \
            || { err "$repo — pull failed"; errors=$((errors+1)); }
    else
        info "cloning $repo..."
        git clone "https://github.com/$GITHUB_USER/$repo.git" "$target" \
            && ok "$repo cloned" \
            || { err "$repo — clone failed"; errors=$((errors+1)); }
    fi
done

[ "$errors" -eq 0 ] && ok "all repos synced" || { err "$errors repo(s) failed"; exit 1; }
