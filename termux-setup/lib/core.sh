# core.sh — shared helpers: colors, logging, guards
# Source this first in every lib module and in setup.sh

# ── Colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  G='\033[32m' R='\033[31m' Y='\033[33m' C='\033[36m' B='\033[1m' Z='\033[0m'
else
  G='' R='' Y='' C='' B='' Z=''
fi

# ── Logging ───────────────────────────────────────────────────────────────────
ok()   { printf "${G}  ✔  %s${Z}\n" "$*"; }
err()  { printf "${R}  ✗  %s${Z}\n" "$*" >&2; }
info() { printf "${C}  →  %s${Z}\n" "$*"; }
warn() { printf "${Y}  !  %s${Z}\n" "$*"; }
step() { printf "\n${B}══ %s ══${Z}\n" "$*"; }
die()  { err "$*"; exit 1; }

# ── Guards ────────────────────────────────────────────────────────────────────
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "comando requerido no encontrado: $1"
}

require_file() {
  [ -f "$1" ] || die "archivo requerido no encontrado: $1"
}

# ── Dry-run support ───────────────────────────────────────────────────────────
# Set DRY_RUN=1 to print commands without executing
DRY_RUN="${DRY_RUN:-0}"
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf "${Y}  [dry]  %s${Z}\n" "$*"
  else
    "$@"
  fi
}
