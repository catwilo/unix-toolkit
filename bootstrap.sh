#!/usr/bin/env bash
# Bootstrap unix-toolkit: clone all active repos from GitHub
# Safe to re-run: pulls existing repos, clones missing ones
# Requires: gh (authenticated), git

set -euo pipefail

GREEN='\033[0;32m' YELLOW='\033[0;33m' RED='\033[0;31m' CYAN='\033[0;36m' NC='\033[0m'

TOOLKIT_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_USER="catwilo"
INDEX_REPO="unix-toolkit"

log_ok()   { echo -e "${GREEN}✓ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
log_err()  { echo -e "${RED}✗ $*${NC}"; }
log_info() { echo -e "${CYAN}→ $*${NC}"; }

# Verify gh auth
if ! gh auth status &>/dev/null; then
  log_err "gh no autenticado. Ejecuta: gh auth login"
  exit 1
fi

log_info "Obteniendo lista de repos de $GITHUB_USER..."
mapfile -t REPOS < <(
  gh repo list "$GITHUB_USER" --limit 100 --json name --jq '.[].name' \
  | grep -v "^${INDEX_REPO}$"
)

log_info "Repos encontrados: ${#REPOS[@]}"
echo

errors=0
for repo in "${REPOS[@]}"; do
  target="$TOOLKIT_DIR/$repo"
  if [ -d "$target/.git" ]; then
    log_warn "$repo — actualizando..."
    if git -C "$target" pull --rebase --autostash 2>/dev/null; then
      log_ok "$repo actualizado"
    else
      log_err "$repo — pull falló, revisa manualmente"
      (( errors++ )) || true
    fi
  else
    log_info "Clonando $repo..."
    if git clone "https://github.com/$GITHUB_USER/$repo.git" "$target"; then
      log_ok "$repo clonado"
    else
      log_err "$repo — clone falló"
      (( errors++ )) || true
    fi
  fi
done

echo
[ "$errors" -eq 0 ] && log_ok "Listo — todos los repos sincronizados" \
                     || log_err "$errors repo(s) fallaron — revisa arriba"
exit "$errors"
