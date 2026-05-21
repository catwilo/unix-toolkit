#!/usr/bin/env bash
# lib/check.sh — dependency and connectivity checks for rsync-folder
# Source this; do not execute directly.

check_dep() {
  local cmd="$1" label="${2:-$1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    log_ok "  $label $(command -v "$cmd")"
    return 0
  else
    log_err "  $label — NO encontrado"
    return 1
  fi
}

check_deps() {
  local missing=0
  log_sep "Dependencias"
  check_dep rsync "rsync       " || (( missing++ )) || true
  check_dep ssh   "ssh         " || (( missing++ )) || true
  if   command -v inotifywait >/dev/null 2>&1; then
    log_ok "  inotifywait  $(command -v inotifywait)"
  elif command -v fswatch     >/dev/null 2>&1; then
    log_ok "  fswatch      $(command -v fswatch)"
  else
    log_err "  inotifywait/fswatch — ninguno encontrado"
    (( missing++ )) || true
  fi
  return "$missing"
}

check_versions() {
  log_sep "Versiones"
  local rsync_ver ssh_ver
  rsync_ver="$(rsync --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo '?')"
  ssh_ver="$(ssh -V 2>&1 | grep -oP 'OpenSSH_\S+' | head -1 || echo '?')"
  log_kv "rsync" "$rsync_ver"
  log_kv "ssh"   "$ssh_ver"
  log_kv "bash"  "${BASH_VERSION}"
}

_ssh_base_opts() {
  local key_file="${1:-}"
  local opts=(
    -o BatchMode=yes
    -o ConnectTimeout=5
    -o StrictHostKeyChecking=accept-new
    -o ServerAliveInterval=10
    -o ServerAliveCountMax=2
  )
  [[ -n "$key_file" ]] && opts+=(-i "$key_file")
  printf '%s\n' "${opts[@]}"
}

check_ssh() {
  local host="$1" user="$2" key_file="${3:-}"
  log_sep "Conectividad SSH"
  log_step "Probando $user@$host (timeout 5s)..."

  local opts=()
  while IFS= read -r opt; do opts+=("$opt"); done < <(_ssh_base_opts "$key_file")

  if ssh "${opts[@]}" "${user}@${host}" "exit 0" >/dev/null 2>&1; then
    log_ok "  SSH $user@$host — accesible"
    return 0
  else
    log_warn "  SSH $user@$host — sin acceso (¿clave SSH configurada?)"
    return 1
  fi
}

# check_remote_dir <host> <user> <path> [key_file]
# FIX: pasar path como argumento posicional al shell remoto para que
# la tilde (~) sea expandida por el shell del SERVIDOR, no del cliente.
# Esto es crítico cuando SOURCE es /storage/emulated/0/Download en Termux
# y DESTINATION es user@host:~/shared — la tilde debe resolverse en el host.
check_remote_dir() {
  local host="$1" user="$2" path="$3" key_file="${4:-}"
  log_step "Verificando directorio remoto: $path"

  local opts=()
  while IFS= read -r opt; do opts+=("$opt"); done < <(_ssh_base_opts "$key_file")

  # Pasar path sin comillas en el comando remoto para que el shell del servidor
  # expanda ~ correctamente. printf %q rompería la expansión (~/shared → \~/shared).
  if ssh "${opts[@]}" "${user}@${host}" \
       "mkdir -p ${path} && test -w ${path}" 2>/dev/null; then
    log_ok "  Directorio remoto OK: $path"
    return 0
  else
    log_warn "  No se pudo verificar/crear: $path"
    return 1
  fi
}

# check_watcher <conf_dir> <install_dir> [profile_name]
# FIX: buscar PID file por perfil (${profile}.watcher.pid), no global.
check_watcher() {
  local conf_dir="$1" install_dir="$2" profile="${3:-}"
  log_sep "Watcher"

  # Si se especifica un perfil, revisar su PID file
  if [[ -n "$profile" ]]; then
    local pid_file="$conf_dir/run/${profile}.watcher.pid"
    if [[ -f "$pid_file" ]]; then
      local pid
      pid="$(< "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        log_ok "  Watcher [$profile] activo (PID $pid)"
        return 0
      else
        log_warn "  PID $pid en archivo pero proceso muerto — limpiando"
        rm -f "$pid_file"
        return 1
      fi
    fi
  fi

  # Fallback: buscar cualquier watcher.sh corriendo para este conf_dir
  if pgrep -f "watcher.sh $conf_dir" >/dev/null 2>&1; then
    local wpids
    wpids="$(pgrep -f "watcher.sh $conf_dir" | tr '\n' ' ')"
    log_ok "  Watcher(s) activos (PIDs: $wpids)"
    return 0
  fi

  log_warn "  Ningún watcher corriendo"
  return 1
}

# _ensure_remote_rsync <user> <host> [key_file]
_ensure_remote_rsync() {
  local user="$1" host="$2" key_file="${3:-}"

  local opts=()
  while IFS= read -r opt; do opts+=("$opt"); done < <(_ssh_base_opts "$key_file")

  if ssh "${opts[@]}" "${user}@${host}" "command -v rsync" >/dev/null 2>&1; then
    return 0
  fi

  log_warn "  rsync no encontrado en el servidor remoto — instalando..."

  local _install_body
  _install_body=$(cat << 'BODY'
set -e
if   command -v apt-get >/dev/null 2>&1; then apt-get install -y rsync
elif command -v apt     >/dev/null 2>&1; then apt install -y rsync
elif command -v pacman  >/dev/null 2>&1; then pacman -S --needed --noconfirm rsync
elif command -v dnf     >/dev/null 2>&1; then dnf install -y rsync
elif command -v yum     >/dev/null 2>&1; then yum install -y rsync
elif command -v zypper  >/dev/null 2>&1; then zypper install -y rsync
elif command -v brew    >/dev/null 2>&1; then brew install rsync
else echo "ERR: gestor de paquetes no soportado en el servidor"; exit 1
fi
BODY
)

  # Intento 1: sudo sin password (root / NOPASSWD)
  if printf '%s\n' "$_install_body" \
       | ssh "${opts[@]}" "${user}@${host}" "sudo -n bash" >/dev/null 2>&1; then
    if ssh "${opts[@]}" "${user}@${host}" "command -v rsync" >/dev/null 2>&1; then
      log_ok "  rsync instalado en ${user}@${host}"
      return 0
    fi
  fi

  # Intento 2: contraseña sudo interactiva
  log_step "  Se requiere contraseña sudo en ${user}@${host}"
  local sudo_pass
  if declare -f _ask_sudo_pass >/dev/null 2>&1; then
    sudo_pass="$(_ask_sudo_pass "$user" "$host")"
  else
    printf '\033[1;33m›\033[0m  Contraseña sudo [%s@%s]: ' "$user" "$host"
    IFS= read -rs sudo_pass </dev/tty
    printf '\n'
  fi

  local install_exit=0
  {
    printf '%s\n' "$sudo_pass"
    printf '%s\n' "$_install_body"
  } | ssh "${opts[@]}" "${user}@${host}" \
        "sudo -S bash 2>&1 | grep -v '^\[sudo\]'" \
  || install_exit=$?

  sudo_pass=""

  if ssh "${opts[@]}" "${user}@${host}" "command -v rsync" >/dev/null 2>&1; then
    log_ok "  rsync instalado correctamente en ${user}@${host}"
    return 0
  else
    log_err "  No se pudo instalar rsync (código $install_exit)"
    log_err "  Instálalo manualmente: sudo apt install rsync"
    return 1
  fi
}

# check_sync_dryrun <src> <dst> <excludes> [key_file]
check_sync_dryrun() {
  local src="$1" dst="$2" excludes="$3" key_file="${4:-}"
  log_sep "Prueba de sincronización (dry-run)"
  log_step "rsync dry-run: $src → $dst"

  if [[ "$dst" == *@*:* ]]; then
    local _r_user="${dst%%@*}"
    local _r_host="${dst#*@}"; _r_host="${_r_host%%:*}"
    _ensure_remote_rsync "$_r_user" "$_r_host" "$key_file" || return 1
  fi

  local ssh_cmd="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"
  [[ -n "$key_file" ]] && ssh_cmd+=" -i $(printf '%q' "$key_file")"

  local output
  if output="$(rsync -az --dry-run \
      --checksum \
      --partial \
      --timeout=30 \
      --exclude-from="$excludes" \
      -e "$ssh_cmd" \
      "$src/" "$dst/" 2>&1)"; then
    local count
    count="$(printf '%s\n' "$output" | grep -c '^' || true)"
    log_ok "  Dry-run exitoso ($count líneas de salida)"
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" | head -10 | while IFS= read -r line; do
        log_kv "" "$line"
      done
      (( count > 10 )) && log_kv "" "... ($((count - 10)) más)"
    else
      log_info "  Sin cambios pendientes"
    fi
    return 0
  else
    log_err "  Dry-run fallido"
    printf '%s\n' "$output" | head -5 | while IFS= read -r line; do
      log_err "  $line"
    done
    return 1
  fi
}
