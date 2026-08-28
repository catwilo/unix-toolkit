#!/usr/bin/env bash
# install.sh -- ut local install
# - installs ut to PATH (atomic copy)
# - configures git templateDir globally
# - populates pre-commit hook in all active repos
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
TEMPLATE_DIR="$HERE/git-templates"

G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; Z=$'\033[0m'
ok()   { printf "%s[OK]%s    %s\n" "$G" "$Z" "$*"; }
warn() { printf "%s[WARN]%s  %s\n" "$Y" "$Z" "$*"; }
err()  { printf "%s[ERROR]%s %s\n" "$R" "$Z" "$*" >&2; }

# -- 1. install ut (symlink to repo source, repo is the only source of truth) --
mkdir -p "$BIN"
chmod +x "$HERE/ut"
ln -sf "$HERE/ut" "$BIN/ut"
ok "ut -> $BIN/ut (symlink to $HERE/ut)"

# -- 2. configure git templateDir globally --
git config --global init.templateDir "$TEMPLATE_DIR"
ok "git templateDir -> $TEMPLATE_DIR"

# -- 3. populate hook in all active repos --
REPOS_TSV="$HERE/repos.tsv"
TOOLS_DIR="$HOME/unix-toolkit-tools"
populated=0
failed=0

populate_repo() {
    local repopath="$1"
    if [[ ! -d "$repopath/.git" ]]; then
        warn "not a git repo, skipping: $repopath"
        return
    fi
    git -C "$repopath" init -q 2>/dev/null
    if [[ -x "$repopath/.git/hooks/pre-commit" ]]; then
        ok "hook populated: $repopath"
        (( populated++ )) || true
    else
        err "hook missing after init: $repopath"
        (( failed++ )) || true
    fi
}

# ut itself
populate_repo "$HERE"

# all repos in unix-toolkit-tools
if [[ -d "$TOOLS_DIR" ]]; then
    for d in "$TOOLS_DIR"/*/; do
        [[ -d "$d/.git" ]] && populate_repo "$d"
    done
fi

echo ""
ok "hooks populated: $populated repos"
[[ $failed -gt 0 ]] && { err "failed: $failed repos"; exit 1; }

# -- 4. verify PATH --
case ":$PATH:" in
    *":$BIN:"*) ok "$BIN already in PATH" ;;
    *) warn "add to PATH: export PATH=\"$BIN:\$PATH\"" ;;
esac

ok "ut install complete"
