#!/usr/bin/env bash
# setup.sh — instalador de rsync-folder
# Uso: ./setup.sh [user@host:/ruta] [-u user] [-i ip] [-p /ruta]
set -euo pipefail

# ─────────────────────────────────────────────
# DEFAULTS
# ─────────────────────────────────────────────
_RF_DEFAULT_USER="u"
_RF_DEFAULT_IP="192.168.x.x"
_RF_DEFAULT_PATH="~/shared"

# ─────────────────────────────────────────────
# RUTAS
# ─────────────────────────────────────────────
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rsync-folder"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/rsync-folder"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─────────────────────────────────────────────
# LOGGING BÁSICO
# ─────────────────────────────────────────────
_raw_ok()   { printf '\033[1;32m✔\033[0m  %s\n' "$*"; }
_raw_info() { printf '\033[1;34m›\033[0m  %s\n' "$*"; }
_raw_warn() { printf '\033[1;33m⚠\033[0m  %s\n' "$*"; }
_raw_err()  { printf '\033[1;31m✖\033[0m  %s\n' "$*" >&2; }
_raw_sep()  { printf '\033[2m────── %s ──────\033[0m\n' "${1:-}"; }
_ask_yn()   {
  local prompt="$1" answer
  printf '\033[1;33m?\033[0m  %s [s/N] ' "$prompt"
  read -r answer </dev/tty
  [[ "$answer" =~ ^[sS]$ ]]
}

# ─────────────────────────────────────────────
# MÓDULO: caché de contraseña sudo para servidor remoto
# ─────────────────────────────────────────────
_SUDO_CACHE_KEY=""
_SUDO_CACHE_FILE=""

_sudo_cache_init() {
  local base_tmp="${TMPDIR:-${XDG_RUNTIME_DIR:-/tmp}}"
  local run_dir="${base_tmp}/rsync-folder-setup-$$"
  mkdir -p "$run_dir" && chmod 700 "$run_dir" || {
    run_dir="$HOME/.rsync-folder-setup-$$"
    mkdir -p "$run_dir" && chmod 700 "$run_dir"
  }
  _SUDO_CACHE_FILE="$run_dir/.sudo_enc"
  _SUDO_CACHE_KEY="$(openssl rand -hex 32 2>/dev/null)"
  trap '_sudo_cache_clear' EXIT
}

_sudo_cache_clear() {
  _SUDO_CACHE_KEY=""
  [[ -n "$_SUDO_CACHE_FILE" && -f "$_SUDO_CACHE_FILE" ]] && rm -f "$_SUDO_CACHE_FILE"
  [[ -n "$_SUDO_CACHE_FILE" ]] && rmdir "$(dirname "$_SUDO_CACHE_FILE")" 2>/dev/null || true
}

_sudo_cache_set() {
  [[ -z "$_SUDO_CACHE_KEY" ]] && _sudo_cache_init
  printf '%s' "$1" \
    | openssl enc -aes-256-cbc -pbkdf2 -pass "pass:${_SUDO_CACHE_KEY}" \
        -out "$_SUDO_CACHE_FILE" 2>/dev/null
  chmod 600 "$_SUDO_CACHE_FILE"
}

_sudo_cache_get() {
  [[ -f "$_SUDO_CACHE_FILE" && -n "$_SUDO_CACHE_KEY" ]] || return 1
  openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:${_SUDO_CACHE_KEY}" \
    -in "$_SUDO_CACHE_FILE" 2>/dev/null || return 1
}

_ask_sudo_pass() {
  local user="$1" host="$2"
  local cached
  if cached="$(_sudo_cache_get)"; then
    printf '%s' "$cached"
    return 0
  fi
  printf '\033[1;33m›\033[0m  Contraseña sudo [%s@%s]: ' "$user" "$host" >/dev/tty
  local pass
  IFS= read -rs pass </dev/tty
  printf '\n' >/dev/tty
  _sudo_cache_set "$pass"
  printf '%s' "$pass"
}

# ─────────────────────────────────────────────
# MÓDULO: parseo de argumento de destino
# ─────────────────────────────────────────────
_ARG_DEST=""
_parse_remote() {
  local _u="" _h="" _p=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--user)
        [[ $# -lt 2 || "$2" == -* ]] && { _raw_err "--user/-u requiere valor"; return 1; }
        _u="$2"; shift 2 ;;
      -i|--ip)
        [[ $# -lt 2 || "$2" == -* ]] && { _raw_err "--ip/-i requiere valor"; return 1; }
        _h="$2"; shift 2 ;;
      -p|--dest)
        [[ $# -lt 2 || "$2" == -* ]] && { _raw_err "--dest/-p requiere valor"; return 1; }
        _p="$2"; shift 2 ;;
      *)
        if [[ "$1" =~ ^([^@:]+)@([^:]+):(.*)$ ]]; then
          _u="${BASH_REMATCH[1]}"; _h="${BASH_REMATCH[2]}"; _p="${BASH_REMATCH[3]}"
        elif [[ "$1" =~ ^u:(.+)$ ]]; then _u="${BASH_REMATCH[1]}"
        elif [[ "$1" =~ ^i:(.+)$ ]]; then _h="${BASH_REMATCH[1]}"
        fi
        shift ;;
    esac
  done
  [[ -n "$_h" ]] && printf '%s' "${_u:+${_u}@}${_h}:${_p:-~/}"
}

if [[ $# -gt 0 ]]; then
  _ARG_DEST="$(_parse_remote "$@")" || { _raw_err "Error en argumentos"; exit 1; }
fi

# ─────────────────────────────────────────────
# MÓDULO: detección de entorno
# ─────────────────────────────────────────────
_detect_env() {
  IS_TERMUX=0
  # Detectar Termux por variable de entorno O por prefix
  if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
    IS_TERMUX=1
  fi

  if   command -v pacman >/dev/null 2>&1; then PM=pacman
  elif command -v apt    >/dev/null 2>&1; then PM=apt
  elif command -v pkg    >/dev/null 2>&1; then PM=pkg
  elif command -v nix    >/dev/null 2>&1; then PM=nix
  else _raw_err "Gestor de paquetes no soportado"; exit 1
  fi

  if [[ $EUID -eq 0 ]] || [[ $PM == pkg ]] || [[ $PM == nix ]] || [[ $IS_TERMUX == 1 ]]; then
    SUDO=""
  else
    SUDO="sudo"
  fi

  _raw_info "Entorno: $PM${IS_TERMUX:+' (Termux)'} | bash ${BASH_VERSION}"
}

# ─────────────────────────────────────────────
# MÓDULO: instalación de dependencias
# ─────────────────────────────────────────────
_need_cmd() { ! command -v "$1" >/dev/null 2>&1; }

_install_deps() {
  _raw_sep "Dependencias"
  local pkgs=()
  case $PM in
    pacman)
      _need_cmd rsync       && pkgs+=(rsync)
      _need_cmd ssh         && pkgs+=(openssh)
      _need_cmd inotifywait && pkgs+=(inotify-tools)
      [[ ${#pkgs[@]} -gt 0 ]] && $SUDO pacman -S --needed --noconfirm "${pkgs[@]}"
      ;;
    apt)
      _need_cmd rsync       && pkgs+=(rsync)
      _need_cmd ssh         && pkgs+=("$([[ $IS_TERMUX == 1 ]] && echo openssh || echo openssh-client)")
      _need_cmd inotifywait && pkgs+=(inotify-tools)
      if [[ ${#pkgs[@]} -gt 0 ]]; then
        [[ $IS_TERMUX == 1 ]] \
          && apt install -y "${pkgs[@]}" \
          || $SUDO apt-get install -y "${pkgs[@]}"
      fi
      ;;
    pkg)
      # Termux pkg
      _need_cmd rsync       && pkgs+=(rsync)
      _need_cmd ssh         && pkgs+=(openssh)
      _need_cmd inotifywait && pkgs+=(inotify-tools)
      [[ ${#pkgs[@]} -gt 0 ]] && pkg install -y "${pkgs[@]}"
      ;;
    nix)
      _need_cmd rsync       && pkgs+=(nixpkgs#rsync)
      _need_cmd ssh         && pkgs+=(nixpkgs#openssh)
      _need_cmd inotifywait && pkgs+=(nixpkgs#inotify-tools)
      [[ ${#pkgs[@]} -gt 0 ]] && nix profile install "${pkgs[@]}"
      ;;
  esac
  if [[ "$(uname)" == "Darwin" ]] && _need_cmd fswatch; then
    command -v brew >/dev/null 2>&1 && brew install fswatch \
      || { _raw_err "Instala fswatch: brew install fswatch"; exit 1; }
  fi

  local missing=0
  for cmd in rsync ssh; do
    if command -v "$cmd" >/dev/null 2>&1; then
      _raw_ok "  $cmd — $(command -v "$cmd")"
    else
      _raw_err "  $cmd — FALTA"
      (( missing++ )) || true
    fi
  done
  if command -v inotifywait >/dev/null 2>&1; then
    _raw_ok "  inotifywait — $(command -v inotifywait)"
  elif command -v fswatch >/dev/null 2>&1; then
    _raw_ok "  fswatch — $(command -v fswatch)"
  else
    _raw_err "  inotifywait/fswatch — FALTA al menos uno"
    (( missing++ )) || true
  fi
  [[ $missing -eq 0 ]] || { _raw_err "$missing dependencias faltantes"; exit 1; }
}

# ─────────────────────────────────────────────
# MÓDULO: instalación de archivos del proyecto
# ─────────────────────────────────────────────
_install_files() {
  mkdir -p "$CONF_DIR/profiles" "$CONF_DIR/run" "$INSTALL_DIR/lib" "$BIN_DIR"

  for lib in log.sh check.sh watcher.sh sync-runner.sh; do
    [[ -f "$SCRIPT_DIR/lib/$lib" ]] \
      || { _raw_err "Archivo fuente faltante: lib/$lib"; exit 1; }
  done

  cp "$SCRIPT_DIR/lib/log.sh"         "$INSTALL_DIR/lib/log.sh"
  cp "$SCRIPT_DIR/lib/check.sh"       "$INSTALL_DIR/lib/check.sh"
  cp "$SCRIPT_DIR/lib/watcher.sh"     "$INSTALL_DIR/lib/watcher.sh"
  cp "$SCRIPT_DIR/lib/sync-runner.sh" "$INSTALL_DIR/lib/sync-runner.sh"
  chmod 755 "$INSTALL_DIR/lib/watcher.sh" "$INSTALL_DIR/lib/sync-runner.sh"
  _raw_ok "  Libs instaladas en $INSTALL_DIR/lib"
}

_install_configs() {
  if [[ -f "$CONF_DIR/excludes.txt" ]]; then
    _raw_info "  excludes.txt existente, preservado"
  else
    cp "$SCRIPT_DIR/excludes.txt" "$CONF_DIR/excludes.txt"
    _raw_ok "  excludes.txt instalado"
  fi
  [[ -f "$CONF_DIR/profiles/template.env" ]] \
    || cp "$SCRIPT_DIR/profiles/template.env" "$CONF_DIR/profiles/template.env"
}

# ─────────────────────────────────────────────
# MÓDULO: gestión del perfil default
# ─────────────────────────────────────────────
_build_dst() {
  if [[ -n "$_ARG_DEST" ]]; then
    printf '%s' "$_ARG_DEST"
  elif [[ -n "${RF_DEST:-}" ]]; then
    printf '%s' "$RF_DEST"
  else
    printf '%s' "${_RF_DEFAULT_USER}@${_RF_DEFAULT_IP}:${_RF_DEFAULT_PATH}"
  fi
}

_build_src() {
  if [[ -n "${RF_SOURCE:-}" ]]; then
    printf '%s' "$RF_SOURCE"
  elif [[ $IS_TERMUX -eq 1 ]] || [[ -d /storage/emulated/0 ]]; then
    printf '%s' "/storage/emulated/0/Download"
  else
    printf '%s' "$HOME/Downloads"
  fi
}

_read_profile_field() {
  local prof_file="$1" field="$2"
  [[ -f "$prof_file" ]] || { printf ''; return 0; }
  grep "^${field}=" "$prof_file" | head -1 | cut -d'"' -f2
}

_read_profile_dst() {
  _read_profile_field "$CONF_DIR/profiles/default.env" "DESTINATION"
}

_active_profile_name() {
  [[ -f "$CONF_DIR/active-profile" ]] && cat "$CONF_DIR/active-profile" || printf 'default'
}

_write_default_profile() {
  local src="$1" dst="$2"
  local dir="${RF_DIRECTION:-push}"
  local deb="${RF_DEBOUNCE:-3}"
  [[ "$dir" =~ ^(push|pull|both)$ ]] \
    || { _raw_err "RF_DIRECTION inválido: '$dir'"; exit 1; }
  mkdir -p "$src"
  [[ "$dst" != *:* ]] && mkdir -p "$dst"

  local prof_file="$CONF_DIR/profiles/default.env"
  (umask 0177; cat > "$prof_file") << EOF
SOURCE="$src"
DESTINATION="$dst"
DIRECTION="$dir"
DEBOUNCE_SEC=$deb
MAX_RETRIES=5
RETRY_DELAY=5
EXCLUDES_FILE="$CONF_DIR/excludes.txt"
BACKUP_ON_OVERWRITE=0
SSH_KEY=""
EOF
  printf 'default' > "$CONF_DIR/active-profile"
  _raw_ok "  Perfil default: $src → $dst [$dir]"
}

_profile_needs_fix() {
  local cur="$1"
  [[ -z "$cur" ]] && return 0
  [[ "$cur" != *:* ]] && return 0
  [[ "$cur" == */data/data/com.termux/* ]] && return 0
  return 1
}

_has_profiles() {
  local f
  for f in "$CONF_DIR/profiles/"*.env; do
    [[ "$(basename "$f")" == "template.env" ]] && continue
    [[ -f "$f" ]] && return 0
  done
  return 1
}

# ─────────────────────────────────────────────
# MÓDULO: configuración de clave SSH
# ─────────────────────────────────────────────
_ssh_probe_key() {
  local user="$1" host="$2" key_file="$3"
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -o IdentitiesOnly=yes \
    -i "$key_file" \
    "${user}@${host}" "exit 0" >/dev/null 2>&1
}

_find_existing_key() {
  local user="$1" host="$2"
  local candidates=()

  local cfg_key
  cfg_key="$(ssh -G "${user}@${host}" 2>/dev/null \
    | awk '/^identityfile / {print $2; exit}')"
  [[ -n "$cfg_key" ]] && candidates+=("${cfg_key/#\~/$HOME}")

  candidates+=(
    "$HOME/.ssh/id_ed25519"
    "$HOME/.ssh/id_ecdsa"
    "$HOME/.ssh/id_rsa"
  )

  local k
  for k in "${candidates[@]}"; do
    [[ -f "$k" ]] || continue
    if _ssh_probe_key "$user" "$host" "$k"; then
      printf '%s' "$k"
      return 0
    fi
  done
  return 1
}

_gen_keypair() {
  local key_path="$1" host="$2"
  local ssh_dir
  ssh_dir="$(dirname "$key_path")"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  rm -f "$key_path" "${key_path}.pub"
  ssh-keygen -t ed25519 -C "rsync-folder@${host}" -N "" -f "$key_path" >/dev/null 2>&1
  chmod 600 "$key_path"
  chmod 644 "${key_path}.pub"
  _raw_ok "  Par generado: $key_path"
}

_copy_key_to_host() {
  local key_path="$1" user="$2" host="$3"
  _raw_info "  Instalando clave pública en $user@$host"

  local ssh_pass
  ssh_pass="$(_ask_sudo_pass "$user" "$host")"

  local pub_key
  pub_key="$(< "${key_path}.pub")"

  local base_tmp="${TMPDIR:-$HOME}"
  local askpass_file="${base_tmp}/.rf_askpass_$$"
  printf '#!/bin/sh\nprintf "%%s\\n" %q\n' "$ssh_pass" > "$askpass_file"
  chmod 700 "$askpass_file"

  local installed=0
  local remote_cmd='mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

  if printf '%s\n' "$pub_key" \
       | SSH_ASKPASS="$askpass_file" \
         SSH_ASKPASS_REQUIRE=force \
         DISPLAY=:0 \
         setsid ssh \
           -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=accept-new \
           -o BatchMode=no \
           "${user}@${host}" \
           "bash -c '$remote_cmd'" 2>/dev/null; then
    installed=1
    _raw_ok "  Clave instalada en $user@$host"
  fi

  rm -f "$askpass_file"

  [[ $installed -eq 1 ]] && return 0
  _raw_err "  Instalación de clave falló — verifica usuario/contraseña y acceso a $host"
  return 1
}

_save_ssh_key_to_profile() {
  local key_path="$1" prof_file="$2"
  [[ -f "$prof_file" ]] || return 1
  python3 - "$prof_file" "$key_path" << 'PYEOF'
import sys, re, os, stat
prof_file, key_path = sys.argv[1], sys.argv[2]
with open(prof_file, 'r') as f:
    content = f.read()
new_line = 'SSH_KEY="{}"'.format(key_path)
if re.search(r'^SSH_KEY=', content, re.MULTILINE):
    content = re.sub(r'^SSH_KEY=.*', new_line, content, flags=re.MULTILINE)
else:
    content = content.rstrip('\n') + '\n' + new_line + '\n'
tmp = prof_file + '.tmp'
orig_mode = stat.S_IMODE(os.stat(prof_file).st_mode)
with open(tmp, 'w') as f:
    f.write(content)
os.chmod(tmp, orig_mode)
os.replace(tmp, prof_file)
PYEOF
}

_setup_ssh_key() {
  local user="$1" host="$2"
  local active_prof
  active_prof="$(_active_profile_name)"
  local prof_file="$CONF_DIR/profiles/${active_prof}.env"
  _raw_sep "Clave SSH"

  local saved_key
  saved_key="$(_read_profile_field "$prof_file" "SSH_KEY")"
  if [[ -n "$saved_key" && -f "$saved_key" ]]; then
    if _ssh_probe_key "$user" "$host" "$saved_key"; then
      _raw_ok "  Clave guardada OK: $saved_key"
      return 0
    else
      _raw_warn "  Clave guardada ($saved_key) ya no funciona — reconfigurando..."
    fi
  fi

  local found_key
  if found_key="$(_find_existing_key "$user" "$host")"; then
    _raw_ok "  Clave existente funciona: $found_key"
    _save_ssh_key_to_profile "$found_key" "$prof_file"
    return 0
  fi

  _raw_warn "  No hay clave SSH para $user@$host"
  _raw_info "  Generando clave ed25519 e instalándola en el servidor..."

  local key_path="$HOME/.ssh/id_ed25519_rsync_folder"
  [[ -f "$key_path" ]] && key_path="$HOME/.ssh/id_ed25519_rf_${host//[^a-zA-Z0-9_]/_}"
  _gen_keypair "$key_path" "$host"
  _copy_key_to_host "$key_path" "$user" "$host" || return 1
  _save_ssh_key_to_profile "$key_path" "$prof_file"
  _raw_ok "  Clave SSH lista y guardada en perfil"
}

# ─────────────────────────────────────────────
# MÓDULO: limpieza y reset completo
# ─────────────────────────────────────────────
_full_reset() {
  [[ -n "$CONF_DIR"    ]] || { _raw_err "CONF_DIR vacío — abortando"; exit 1; }
  [[ -n "$INSTALL_DIR" ]] || { _raw_err "INSTALL_DIR vacío — abortando"; exit 1; }
  [[ -n "$BIN_DIR"     ]] || { _raw_err "BIN_DIR vacío — abortando"; exit 1; }

  _raw_info "  Deteniendo watchers..."
  pkill -f "$INSTALL_DIR/lib/watcher.sh" 2>/dev/null || true
  systemctl --user stop    "rsync-folder@*" 2>/dev/null || true
  systemctl --user disable "rsync-folder@*" 2>/dev/null || true
  # Compatibilidad con nombre antiguo de servicio
  systemctl --user stop    rsync-folder 2>/dev/null || true
  systemctl --user disable rsync-folder 2>/dev/null || true

  _raw_info "  Eliminando instalación anterior..."
  rm -rf "$CONF_DIR" "$INSTALL_DIR"
  rm -f  "$BIN_DIR/rsync-folder"

  _raw_info "  Recreando estructura..."
  mkdir -p "$CONF_DIR/profiles" "$CONF_DIR/run" "$INSTALL_DIR/lib" "$BIN_DIR"
  _raw_ok "  Reset completo"
}

# ─────────────────────────────────────────────
# MÓDULO: instalación del CLI
# ─────────────────────────────────────────────
_install_cli() {
# El CLI se genera con sed reemplazando los placeholders de rutas.
# Las variables __CONF_DIR__ y __INSTALL_DIR__ se sustituyen después con sed.
cat > "$BIN_DIR/rsync-folder" << 'CLIEOF'
#!/usr/bin/env bash
# rsync-folder CLI — comando principal
# Generado por setup.sh — no editar directamente.
set -euo pipefail

CONF_DIR="__CONF_DIR__"
INSTALL_DIR="__INSTALL_DIR__"

source "$INSTALL_DIR/lib/log.sh"
source "$INSTALL_DIR/lib/check.sh"

# ── helpers ──────────────────────────────────────────────────────────────────

_active_profile() {
  [[ -f "$CONF_DIR/active-profile" ]] && cat "$CONF_DIR/active-profile" || printf 'default'
}

_load_profile() {
  local p="${1:-$(_active_profile)}"
  local prof_file="$CONF_DIR/profiles/${p}.env"
  [[ -f "$prof_file" ]] || { log_err "Perfil no encontrado: $p"; exit 1; }
  source "$prof_file"
  EXCLUDES_FILE="${EXCLUDES_FILE:-$CONF_DIR/excludes.txt}"
  SSH_KEY="${SSH_KEY:-}"
}

_parse_dest() {
  local dst="$1"
  if [[ "$dst" =~ ^([^@]+)@([^:]+):(.*)$ ]]; then
    _DEST_USER="${BASH_REMATCH[1]}"
    _DEST_HOST="${BASH_REMATCH[2]}"
    _DEST_PATH="${BASH_REMATCH[3]}"
  else
    _DEST_USER="" _DEST_HOST="" _DEST_PATH="$dst"
  fi
}

_ssh_probe_key() {
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new \
    -o IdentitiesOnly=yes \
    -i "$3" "${1}@${2}" "exit 0" >/dev/null 2>&1
}

_save_ssh_key() {
  local key_path="$1" prof_file="$2"
  [[ -f "$prof_file" ]] || { log_err "Perfil no encontrado: $prof_file"; return 1; }
  python3 - "$prof_file" "$key_path" << 'PYEOF'
import sys, re, os, stat
prof_file, key_path = sys.argv[1], sys.argv[2]
with open(prof_file, 'r') as f:
    content = f.read()
new_line = 'SSH_KEY="{}"'.format(key_path)
if re.search(r'^SSH_KEY=', content, re.MULTILINE):
    content = re.sub(r'^SSH_KEY=.*', new_line, content, flags=re.MULTILINE)
else:
    content = content.rstrip('\n') + '\n' + new_line + '\n'
tmp = prof_file + '.tmp'
orig_mode = stat.S_IMODE(os.stat(prof_file).st_mode)
with open(tmp, 'w') as f:
    f.write(content)
os.chmod(tmp, orig_mode)
os.replace(tmp, prof_file)
PYEOF
}

# ── watch ─────────────────────────────────────────────────────────────────────
# FIX: acepta perfil como argumento opcional.
# FIX: guarda PID del proceso watcher en PID file por perfil.
# FIX: NO usa exec (que reemplaza el proceso y pierde el PID correcto);
#      corre watcher.sh directamente sin exec para que el PID sea el correcto.
_cmd_watch() {
  local prof="${1:-$(_active_profile)}"
  [[ -f "$CONF_DIR/profiles/${prof}.env" ]] \
    || { log_err "Perfil no encontrado: $prof"; exit 1; }

  log_step "Iniciando watcher (perfil: $prof)"

  # Matar watcher previo del mismo perfil si existe
  local pid_file="$CONF_DIR/run/${prof}.watcher.pid"
  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid="$(< "$pid_file")"
    if kill -0 "$old_pid" 2>/dev/null; then
      log_info "Deteniendo watcher anterior (PID $old_pid)..."
      kill "$old_pid" 2>/dev/null || true
      sleep 1
    fi
    rm -f "$pid_file"
  fi

  # watcher.sh escribe su propio PID file al arrancar
  bash "$INSTALL_DIR/lib/watcher.sh" "$CONF_DIR" "$prof"
}

_cmd_watch_bg() {
  local prof="${1:-$(_active_profile)}"
  [[ -f "$CONF_DIR/profiles/${prof}.env" ]] \
    || { log_err "Perfil no encontrado: $prof"; exit 1; }

  log_step "Iniciando watcher en background (perfil: $prof)"

  local pid_file="$CONF_DIR/run/${prof}.watcher.pid"
  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid="$(< "$pid_file")"
    if kill -0 "$old_pid" 2>/dev/null; then
      log_warn "Watcher ya corriendo (PID $old_pid) — usa 'stop $prof' primero"
      return 0
    fi
    rm -f "$pid_file"
  fi

  local log_file="$CONF_DIR/watcher-${prof}.log"
  nohup bash "$INSTALL_DIR/lib/watcher.sh" "$CONF_DIR" "$prof" \
    > "$log_file" 2>&1 &
  local watcher_pid=$!
  # watcher.sh escribe su propio PID file, pero como fallback guardamos el nohup pid
  sleep 0.5
  if ! kill -0 "$watcher_pid" 2>/dev/null; then
    log_err "Watcher terminó inmediatamente — revisa: tail -20 $log_file"
    return 1
  fi
  log_ok "Watcher [$prof] en background (PID $watcher_pid) — log: $log_file"
}

# ── sync ─────────────────────────────────────────────────────────────────────
_cmd_sync() {
  local dir="${1:-push}" prof="${2:-$(_active_profile)}"
  log_step "Sincronización manual [$dir] (perfil: $prof)"
  bash "$INSTALL_DIR/lib/sync-runner.sh" "$CONF_DIR" "$prof" "$dir"
}

# ── status ────────────────────────────────────────────────────────────────────
_cmd_status() {
  local prof="${1:-$(_active_profile)}"
  _load_profile "$prof"
  _parse_dest "$DESTINATION"

  log_sep "rsync-folder status"
  log_kv "Perfil activo"  "$prof"
  log_kv "Fuente"         "$SOURCE"
  log_kv "Destino"        "$DESTINATION"
  log_kv "Dirección"      "${DIRECTION:-push}"
  log_kv "Debounce"       "${DEBOUNCE_SEC:-3}s"
  log_kv "Clave SSH"      "${SSH_KEY:-(ninguna)}"

  check_watcher "$CONF_DIR" "$INSTALL_DIR" "$prof"

  # Mostrar estado de todos los perfiles con watcher activo
  log_sep "Todos los watchers"
  local any_running=0
  for f in "$CONF_DIR/profiles/"*.env; do
    [[ "$(basename "$f")" == "template.env" ]] && continue
    local pname
    pname="$(basename "$f" .env)"
    local ppid_file="$CONF_DIR/run/${pname}.watcher.pid"
    if [[ -f "$ppid_file" ]]; then
      local ppid
      ppid="$(< "$ppid_file")"
      if kill -0 "$ppid" 2>/dev/null; then
        log_ok "  [$pname] PID $ppid — activo"
        any_running=1
      else
        log_warn "  [$pname] PID muerto (PID file obsoleto)"
      fi
    else
      log_info "  [$pname] no iniciado"
    fi
  done
  [[ $any_running -eq 0 ]] && log_warn "  Ningún watcher activo"

  if [[ -f "$CONF_DIR/sync-stats.tsv" ]]; then
    log_sep "Últimas sincronizaciones"
    tail -5 "$CONF_DIR/sync-stats.tsv" | while IFS=$'\t' read -r ts p files size; do
      log_kv "$ts" "perfil=$p  archivos=$files  tamaño=$size"
    done
  else
    log_info "Sin sincronizaciones registradas aún"
  fi

  if [[ -f "$CONF_DIR/sync.log" ]]; then
    log_sep "Últimas entradas del log"
    tail -5 "$CONF_DIR/sync.log" | while IFS= read -r line; do
      log_kv "" "$line"
    done
  fi
}

# ── check ─────────────────────────────────────────────────────────────────────
_cmd_check() {
  local prof="${1:-$(_active_profile)}"
  _load_profile "$prof"
  _parse_dest "$DESTINATION"

  log_sep "Diagnóstico completo — perfil: $prof"
  check_deps
  check_versions

  if [[ -n "$_DEST_HOST" ]]; then
    check_ssh      "$_DEST_HOST" "$_DEST_USER" "$SSH_KEY"
    check_remote_dir "$_DEST_HOST" "$_DEST_USER" "$_DEST_PATH" "$SSH_KEY"
    check_sync_dryrun "$SOURCE" "$DESTINATION" "$EXCLUDES_FILE" "$SSH_KEY"
  else
    log_warn "Destino local — omitiendo checks SSH"
  fi

  check_watcher "$CONF_DIR" "$INSTALL_DIR" "$prof"
  log_sep "Fin diagnóstico"
}

# ── logs ──────────────────────────────────────────────────────────────────────
_cmd_logs() {
  local n="${1:-30}" prof="${2:-}"
  if [[ -n "$prof" ]]; then
    local wlog="$CONF_DIR/watcher-${prof}.log"
    log_sep "Últimas $n líneas — watcher-${prof}.log"
    [[ -f "$wlog" ]] && tail -n "$n" "$wlog" || log_warn "Sin log para perfil $prof"
  fi
  log_sep "Últimas $n líneas — sync.log"
  [[ -f "$CONF_DIR/sync.log" ]] \
    && tail -n "$n" "$CONF_DIR/sync.log" \
    || log_warn "sync.log no existe aún"
}

_cmd_tail() {
  local prof="${1:-}"
  if [[ -n "$prof" ]]; then
    local wlog="$CONF_DIR/watcher-${prof}.log"
    log_step "Siguiendo watcher-${prof}.log (Ctrl+C para salir)"
    [[ -f "$wlog" ]] && tail -f "$wlog" || log_err "Sin log para perfil $prof"
    return
  fi
  log_step "Siguiendo sync.log en tiempo real (Ctrl+C para salir)"
  [[ -f "$CONF_DIR/sync.log" ]] \
    && tail -f "$CONF_DIR/sync.log" \
    || log_err "sync.log no existe aún"
}

# ── stop ──────────────────────────────────────────────────────────────────────
_cmd_stop() {
  local prof="${1:-}"
  if [[ -n "$prof" ]]; then
    log_step "Deteniendo watcher [$prof]..."
    local pid_file="$CONF_DIR/run/${prof}.watcher.pid"
    if [[ -f "$pid_file" ]]; then
      local pid
      pid="$(< "$pid_file")"
      kill "$pid" 2>/dev/null && log_ok "Watcher [$prof] (PID $pid) detenido" \
        || log_warn "PID $pid ya no existía"
      rm -f "$pid_file"
    else
      # Fallback: buscar por nombre de proceso
      pkill -f "watcher.sh $CONF_DIR $prof" 2>/dev/null \
        && log_ok "Watcher [$prof] detenido" \
        || log_warn "Watcher [$prof] no estaba corriendo"
    fi
  else
    log_step "Deteniendo TODOS los watchers..."
    # Systemd (con @ template)
    systemctl --user stop "rsync-folder@*" 2>/dev/null || true
    systemctl --user stop  rsync-folder    2>/dev/null || true
    # PIDs directos
    pkill -f "watcher.sh $CONF_DIR" 2>/dev/null || true
    rm -f "$CONF_DIR/run/"*.watcher.pid
    log_ok "Todos los watchers detenidos"
  fi
}

# ── profile ───────────────────────────────────────────────────────────────────
_cmd_profile_show() {
  local prof="${1:-$(_active_profile)}"
  log_sep "Perfil: $prof"
  local prof_file="$CONF_DIR/profiles/${prof}.env"
  [[ -f "$prof_file" ]] || { log_err "Perfil no encontrado: $prof"; exit 1; }
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^[[:space:]]*# || -z "${key// }" ]] && continue
    local display_val="${val//\"/}"
    if [[ "$key" == "SSH_KEY" && -n "$display_val" ]]; then
      local dir base
      dir="$(dirname "$display_val")"
      base="$(basename "$display_val")"
      display_val="$dir/***${base: -6}"
    fi
    log_kv "$key" "$display_val"
  done < "$prof_file"
}

_cmd_profile_list() {
  log_sep "Perfiles disponibles"
  local active
  active="$(_active_profile)"
  for f in "$CONF_DIR/profiles/"*.env; do
    [[ "$(basename "$f")" == "template.env" ]] && continue
    local name pname_file pid_status=""
    name="$(basename "$f" .env)"
    pname_file="$CONF_DIR/run/${name}.watcher.pid"
    if [[ -f "$pname_file" ]]; then
      local ppid
      ppid="$(< "$pname_file")"
      kill -0 "$ppid" 2>/dev/null \
        && pid_status=" ${_C_OK}[corriendo PID $ppid]${_C_RESET}" \
        || pid_status=" ${_C_WARN}[PID muerto]${_C_RESET}"
    fi
    if [[ "$name" == "$active" ]]; then
      printf "  ${_C_OK}▶${_C_RESET}  ${_C_BOLD}%s${_C_RESET} (activo)%b\n" "$name" "$pid_status"
    else
      printf "     %s%b\n" "$name" "$pid_status"
    fi
  done
}

# ── switch ────────────────────────────────────────────────────────────────────
# FIX: se elimina 'local' fuera de función (causaba error de sintaxis en bash).
_cmd_switch() {
  local prof="${1:-}"
  [[ -n "$prof" ]] || { log_err "Uso: rsync-folder switch <perfil>"; exit 1; }
  [[ -f "$CONF_DIR/profiles/${prof}.env" ]] \
    || { log_err "Perfil no encontrado: $prof"; exit 1; }
  printf '%s' "$prof" > "$CONF_DIR/active-profile"
  # Recargar en caliente todos los watchers del perfil anterior (SIGUSR1)
  if pgrep -f "watcher.sh $CONF_DIR" >/dev/null 2>&1; then
    pkill -USR1 -f "watcher.sh $CONF_DIR"
    log_ok "Perfil activo: $prof (watchers recargados)"
  else
    log_ok "Perfil activo: $prof (aplica en el próximo watch)"
  fi
}

# ── ssh-key ───────────────────────────────────────────────────────────────────
_cmd_ssh_key() {
  local sub="${2:-show}"
  local prof
  prof="$(_active_profile)"
  _load_profile "$prof"
  _parse_dest "$DESTINATION"
  local prof_file="$CONF_DIR/profiles/${prof}.env"

  case "$sub" in
    show)
      log_sep "Clave SSH — perfil '$prof'"
      if [[ -z "$SSH_KEY" ]]; then
        log_warn "SSH_KEY no configurada"
        log_info "Usa: rsync-folder ssh-key set <ruta>"
      else
        local dir base masked
        dir="$(dirname "$SSH_KEY")"
        base="$(basename "$SSH_KEY")"
        masked="$dir/***${base: -6}"
        log_kv "Ruta enmascarada" "$masked"
        log_kv "Ruta completa"    "$SSH_KEY"
        if [[ -f "$SSH_KEY" ]]; then
          local perms
          perms="$(stat -c '%a' "$SSH_KEY" 2>/dev/null || stat -f '%A' "$SSH_KEY" 2>/dev/null || echo '???')"
          log_kv "Permisos" "$perms"
          [[ "$perms" == "600" ]] \
            && log_ok "  Permisos correctos (600)" \
            || log_warn "  Permisos inseguros — ejecuta: chmod 600 $SSH_KEY"
        else
          log_warn "  Archivo NO encontrado en disco"
        fi
      fi
      ;;
    set)
      [[ -n "${3:-}" ]] || { log_err "Uso: rsync-folder ssh-key set <ruta>"; exit 1; }
      local key_path="${3/#\~/$HOME}"
      [[ -f "$key_path" ]] || { log_err "Archivo no encontrado: $key_path"; exit 1; }
      local perms
      perms="$(stat -c '%a' "$key_path" 2>/dev/null || stat -f '%A' "$key_path" 2>/dev/null || echo '???')"
      if [[ "$perms" != '???' ]] && (( 10#$perms & 0044 )); then
        log_warn "Permisos inseguros ($perms) — ajustando a 600"
        chmod 600 "$key_path"
      fi
      _save_ssh_key "$key_path" "$prof_file"
      log_ok "SSH_KEY actualizada en perfil '$prof'"
      if [[ -n "$_DEST_HOST" ]]; then
        log_step "Probando clave contra $_DEST_USER@$_DEST_HOST..."
        if _ssh_probe_key "$_DEST_USER" "$_DEST_HOST" "$key_path"; then
          log_ok "  Conexión exitosa"
        else
          log_warn "  La clave no funciona — ¿está en authorized_keys del host?"
        fi
      fi
      ;;
    test)
      [[ -n "$SSH_KEY" ]] || { log_err "SSH_KEY no configurada en perfil '$prof'"; exit 1; }
      [[ -n "$_DEST_HOST" ]] || { log_err "Destino '$DESTINATION' no es remoto"; exit 1; }
      [[ -f "$SSH_KEY" ]] || { log_err "Archivo de clave no encontrado: $SSH_KEY"; exit 1; }
      log_step "Probando conexión → ${_DEST_USER}@${_DEST_HOST}..."
      if _ssh_probe_key "$_DEST_USER" "$_DEST_HOST" "$SSH_KEY"; then
        log_ok "  SSH OK con $SSH_KEY"
      else
        log_err "  Falló — verifica que la clave esté en authorized_keys del host"
        exit 1
      fi
      ;;
    *) log_err "Uso: rsync-folder ssh-key {show|set <ruta>|test}"; exit 1 ;;
  esac
}

# ── debounce ──────────────────────────────────────────────────────────────────
# Permite leer o cambiar DEBOUNCE_SEC en caliente sin editar el .env a mano.
# El cambio persiste en el perfil y se aplica en el próximo arranque del watcher.
# Si el watcher está corriendo, se le envía SIGUSR1 para que recargue el perfil.
_cmd_debounce() {
  local sub="${1:-show}"
  local prof
  prof="$(_active_profile)"
  local prof_file="$CONF_DIR/profiles/${prof}.env"
  [[ -f "$prof_file" ]] || { log_err "Perfil no encontrado: $prof_file"; exit 1; }

  case "$sub" in
    show)
      local current
      current="$(grep '^DEBOUNCE_SEC=' "$prof_file" | cut -d'=' -f2 | tr -d '"' | head -1)"
      log_sep "Debounce — perfil '$prof'"
      log_kv "Valor actual" "${current:-2}s"
      log_info "Cambia con: rsync-folder debounce set <segundos>"
      ;;
    set)
      local val="${2:-}"
      [[ -n "$val" ]] || { log_err "Uso: rsync-folder debounce set <segundos>"; exit 1; }
      [[ "$val" =~ ^[0-9]+$ ]] || { log_err "Valor inválido: '$val' — debe ser un número entero"; exit 1; }
      (( val >= 1 )) || { log_err "Mínimo 1 segundo"; exit 1; }
      (( val <= 60 )) || { log_warn "Debounce de ${val}s es muy alto — ¿estás seguro?"; }

      # Actualizar o añadir DEBOUNCE_SEC en el perfil
      if grep -q '^DEBOUNCE_SEC=' "$prof_file"; then
        sed -i "s/^DEBOUNCE_SEC=.*/DEBOUNCE_SEC=${val}/" "$prof_file"
      else
        printf 'DEBOUNCE_SEC=%s\n' "$val" >> "$prof_file"
      fi
      log_ok "DEBOUNCE_SEC=${val}s guardado en perfil '$prof'"

      # Si el watcher está corriendo, recargarlo en caliente con SIGUSR1
      local pid_file="$CONF_DIR/run/${prof}.watcher.pid"
      if [[ -f "$pid_file" ]]; then
        local pid
        pid="$(< "$pid_file")"
        if kill -0 "$pid" 2>/dev/null; then
          kill -USR1 "$pid" 2>/dev/null && \
            log_ok "Watcher recargado en caliente (PID $pid)" || \
            log_warn "No se pudo recargar el watcher — reinícialo para aplicar"
        else
          log_info "Watcher no está corriendo — el cambio aplica al próximo arranque"
        fi
      else
        log_info "Watcher no está corriendo — el cambio aplica al próximo arranque"
      fi
      ;;
    *)
      log_err "Uso: rsync-folder debounce {show|set <segundos>}"
      exit 1
      ;;
  esac
}

# ── help ──────────────────────────────────────────────────────────────────────
_cmd_help() {
  cat << HELPEOF

  ${_C_BOLD}rsync-folder${_C_RESET} — sincronización automática vía rsync+SSH

  ${_C_CYAN}Monitoreo${_C_RESET}
    watch [perfil]              Iniciar watcher en foreground (perfil activo o el indicado)
    watch-bg [perfil]           Iniciar watcher en background
    status [perfil]             Estado del watcher + últimas sincronizaciones
    check [perfil]              Diagnóstico completo (deps, SSH, dry-run)
    logs [n] [perfil]           Últimas n entradas del log (default: 30)
    tail [perfil]               Seguir el log en tiempo real

  ${_C_CYAN}Sincronización${_C_RESET}
    sync [both|push|pull] [perfil]  Forzar sincronización (default: both)

  ${_C_CYAN}Configuración${_C_RESET}
    debounce show               Mostrar el debounce actual del perfil activo
    debounce set <segundos>     Cambiar el debounce (aplica en caliente si el watcher corre)

  ${_C_CYAN}¿Qué es el debounce?${_C_RESET}
    Tiempo de espera entre el último cambio detectado y el inicio de la
    sincronización. Evita lanzar rsync decenas de veces cuando se copian
    muchos archivos a la vez (ej: 500 fotos).

    Ejemplo con debounce=2s:
      foto_001 llega  → timer empieza: 2s
      foto_002 llega  → timer se reinicia: 2s
      foto_003 llega  → timer se reinicia: 2s
      ...silencio 2s  → rsync se lanza UNA sola vez con todas las fotos

    Valores recomendados:
      1s  — máxima velocidad, puede partir archivos grandes en tránsito
      2s  — equilibrio óptimo (default)
      5s  — redes lentas o archivos muy grandes

  ${_C_CYAN}Perfiles${_C_RESET}
    profile show [nombre]       Mostrar valores del perfil
    profile list                Listar todos los perfiles con estado de watcher
    profile new <nombre>        Crear perfil desde template
    switch <perfil>             Cambiar perfil activo (recarga watcher en caliente)

  ${_C_CYAN}Clave SSH${_C_RESET}
    ssh-key show                Mostrar clave SSH configurada
    ssh-key set <ruta>          Cambiar clave SSH (persiste en perfil)
    ssh-key test                Probar conexión con la clave guardada

  ${_C_CYAN}Control${_C_RESET}
    stop [perfil]               Detener watcher del perfil (o todos si no se indica)

  ${_C_CYAN}Ejemplos multi-perfil${_C_RESET}
    rsync-folder watch-bg trabajo      # watcher perfil 'trabajo' en bg
    rsync-folder watch-bg personal     # watcher perfil 'personal' en bg
    rsync-folder status                # ver estado de todos los perfiles
    rsync-folder sync push trabajo     # sync manual del perfil 'trabajo'
    rsync-folder stop trabajo          # detener solo el perfil 'trabajo'
    rsync-folder debounce set 2        # cambiar debounce a 2s en caliente

HELPEOF
}

# ── dispatch ──────────────────────────────────────────────────────────────────
case "${1:-help}" in
  watch)      _cmd_watch    "${2:-}" ;;
  watch-bg)   _cmd_watch_bg "${2:-}" ;;
  sync)       _cmd_sync     "${2:-both}" "${3:-}" ;;
  status)     _cmd_status   "${2:-}" ;;
  check)      _cmd_check    "${2:-}" ;;
  logs)       _cmd_logs     "${2:-30}" "${3:-}" ;;
  tail)       _cmd_tail     "${2:-}" ;;
  stop)       _cmd_stop     "${2:-}" ;;
  ssh-key)    _cmd_ssh_key  "$@" ;;
  switch)     _cmd_switch   "${2:-}" ;;
  profile)
    case "${2:-show}" in
      show) _cmd_profile_show "${3:-}" ;;
      list) _cmd_profile_list ;;
      new)
        [[ -n "${3:-}" ]] || { log_err "Uso: rsync-folder profile new <nombre>"; exit 1; }
        cp "$CONF_DIR/profiles/template.env" "$CONF_DIR/profiles/${3}.env"
        chmod 600 "$CONF_DIR/profiles/${3}.env"
        log_ok "Perfil creado: $CONF_DIR/profiles/${3}.env"
        log_info "Edítalo y luego: rsync-folder watch-bg ${3}"
        ;;
      *) log_err "Uso: rsync-folder profile {show|list|new <nombre>}"; exit 1 ;;
    esac
    ;;
  help|--help|-h) _cmd_help ;;
  debounce)   _cmd_debounce  "${2:-show}" "${3:-}" ;;
  *) log_err "Comando desconocido: ${1}"; _cmd_help; exit 1 ;;
esac
CLIEOF

  sed -i "s|__CONF_DIR__|${CONF_DIR}|g"      "$BIN_DIR/rsync-folder"
  sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "$BIN_DIR/rsync-folder"
  chmod 755 "$BIN_DIR/rsync-folder"
  _raw_ok "  CLI instalado en $BIN_DIR/rsync-folder"
}

# ─────────────────────────────────────────────
# MÓDULO: arranque del watcher
# ─────────────────────────────────────────────
_start_watcher() {
  # Matar watchers anteriores
  pkill -f "$INSTALL_DIR/lib/watcher.sh" 2>/dev/null || true

  local active_prof
  active_prof="$(_active_profile_name)"
  local log_file="$CONF_DIR/watcher-${active_prof}.log"

  if systemctl --user daemon-reload >/dev/null 2>&1; then
    # Sistemas con systemd: instalar unidad template
    local svc_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$svc_dir"
    cp "$SCRIPT_DIR/service/rsync-folder@.service" "$svc_dir/rsync-folder@.service"
    # Remover unidad antigua (sin @) si existe
    systemctl --user disable rsync-folder.service 2>/dev/null || true
    rm -f "$svc_dir/rsync-folder.service"
    systemctl --user daemon-reload
    systemctl --user enable --now "rsync-folder@${active_prof}.service"
    _raw_ok "  Watcher via systemd (rsync-folder@${active_prof}.service)"
  else
    # Termux y sistemas sin systemd: nohup
    nohup bash "$INSTALL_DIR/lib/watcher.sh" "$CONF_DIR" "$active_prof" \
      > "$log_file" 2>&1 &
    local watcher_pid=$!
    sleep 0.5
    if kill -0 "$watcher_pid" 2>/dev/null; then
      _raw_ok "  Watcher [$active_prof] en background (PID $watcher_pid)"
      _raw_info "  Log: $log_file"
    else
      _raw_err "  Watcher terminó inmediatamente — revisa: tail -20 $log_file"
    fi
  fi
}

# ─────────────────────────────────────────────
# FLUJO PRINCIPAL
# ─────────────────────────────────────────────
_raw_sep "rsync-folder setup"
_detect_env
_install_deps

_raw_sep "Archivos"
_install_files

_raw_sep "Configuración"
_cur_dst="$(_read_profile_dst)"
_new_src="$(_build_src)"
_new_dst="$(_build_dst)"

if ! _has_profiles; then
  _raw_info "  Primer uso — generando perfil default"
  _install_configs
  _write_default_profile "$_new_src" "$_new_dst"

elif _profile_needs_fix "$_cur_dst"; then
  _raw_warn "  Configuración inválida detectada: '${_cur_dst:-vacío}'"
  _raw_info "  Aplicando reset automático..."
  _full_reset
  _install_files
  _install_configs
  _write_default_profile "$_new_src" "$_new_dst"

else
  _raw_info "  Configuración existente:"
  printf '  \033[2m%-16s\033[0m \033[0;37m%s\033[0m\n' "DESTINATION" "$_cur_dst"
  if _ask_yn "¿Borrar todo y reinstalar limpio?"; then
    _full_reset
    _install_files
    _install_configs
    _write_default_profile "$_new_src" "$_new_dst"
  else
    _raw_info "  Actualizando libs y CLI (perfiles preservados)..."
    _install_files
    _install_configs
    _raw_ok "  Configuración preservada"
  fi
fi

# Garantizar active-profile válido
if [[ ! -f "$CONF_DIR/active-profile" ]]; then
  for _ap in "$CONF_DIR/profiles/"*.env; do
    [[ "$(basename "$_ap")" == "template.env" ]] && continue
    basename "$_ap" .env > "$CONF_DIR/active-profile"; break
  done
fi

# Configurar clave SSH si el destino es remoto
_active_dst="$(_read_profile_dst)"
if [[ "$_active_dst" == *@*:* ]]; then
  _ssh_user="${_active_dst%%@*}"
  _ssh_host="${_active_dst#*@}"; _ssh_host="${_ssh_host%%:*}"
  _setup_ssh_key "$_ssh_user" "$_ssh_host"
fi

_raw_sep "CLI"
_install_cli

_raw_sep "Watcher"
_start_watcher

_raw_sep "Listo"
_raw_ok "  Instalación completa"
printf '\n  \033[1mComandos esenciales:\033[0m\n'
printf '    rsync-folder check              # diagnóstico completo\n'
printf '    rsync-folder status             # estado + últimas syncs\n'
printf '    rsync-folder watch              # watcher en foreground\n'
printf '    rsync-folder watch-bg           # watcher en background\n'
printf '    rsync-folder tail               # ver log en vivo\n'
printf '    rsync-folder sync               # forzar sync manual\n'
printf '\n  \033[1mMulti-perfil:\033[0m\n'
printf '    rsync-folder profile new trabajo\n'
printf '    nano ~/.config/rsync-folder/profiles/trabajo.env\n'
printf '    rsync-folder watch-bg trabajo   # watcher independiente\n'
printf '    rsync-folder status             # ver todos los perfiles\n'
printf '\n'

# Diagnóstico post-instalación
_raw_sep "Diagnóstico post-instalación"
if [[ -x "$BIN_DIR/rsync-folder" ]]; then
  "$BIN_DIR/rsync-folder" check
else
  _raw_warn "  CLI no disponible aún — ejecuta: rsync-folder check"
fi
