#!/bin/sh
# output.sh — render discovery results and drive post-display registration
#
# render_output: prints NET / HOSTS table / DEVICES table / CONNECT section.
# prompt_new_hosts: called after render_output; asks alias+user for each
#   new host interactively, then writes to devices.db.

_W_IP=16      # "10.140.25.144"
_W_TYPE=12    # "android-ssh"
_W_ALIAS=8    # "(deb)"
_W_PORT=4     # "8022"
_W_TTL=3      # "64"

_pad() { printf '%*s' "$1" '' | tr ' ' '-'; }

render_output() {
    printf '\n'
    printf '  NET   %s\n'       "${SUBNET:-?}"
    printf '  GW    %s\n'       "${GW_IP:-?}"
    printf '  SELF  %s  [%s]\n' "${MY_IP:-?}" "${PRIMARY_IFACE:-?}"
    printf '\n'

    _hosts_db="$BASE/state/hosts.db"
    _devdb="$BASE/state/devices.db"

    if [ ! -f "$_hosts_db" ] || [ ! -s "$_hosts_db" ]; then
        printf '  No hosts found.\n\n'
        return 0
    fi

    _n="$(wc -l < "$_hosts_db" | tr -d ' ')"
    printf '  HOSTS  %s discovered\n\n' "$_n"

    # Hosts table header
    printf '  %-*s  %-*s  %-*s  %-*s  %s\n' \
        "$_W_IP"    "IP" \
        "$_W_TYPE"  "TYPE" \
        "$_W_ALIAS" "ALIAS" \
        "$_W_PORT"  "PORT" \
        "TTL"
    printf '  %s  %s  %s  %s  %s\n' \
        "$(_pad "$_W_IP")" "$(_pad "$_W_TYPE")" "$(_pad "$_W_ALIAS")" \
        "$(_pad "$_W_PORT")" "$(_pad "$_W_TTL")"

    while IFS='|' read -r _ip _type _ttl _ssh_port _all_ports; do
        [ -n "$_ip" ] || continue

        _alias=""
        if [ -f "$_devdb" ]; then
            _alias="$(awk -F'|' -v ip="$_ip" '
                /^[[:space:]]*$/ { next }
                /^#/             { next }
                $2 == ip         { print $1; exit }
            ' "$_devdb" 2>/dev/null)"
        fi

        _alias_disp=""
        [ -n "$_alias" ] && _alias_disp="(${_alias})"

        _port_disp="${_ssh_port:-?}"
        [ "$_port_disp" = "0" ] && _port_disp="-"

        printf '  %-*s  %-*s  %-*s  %-*s  %s\n' \
            "$_W_IP"    "$_ip" \
            "$_W_TYPE"  "$_type" \
            "$_W_ALIAS" "$_alias_disp" \
            "$_W_PORT"  "$_port_disp" \
            "${_ttl:-?}"

        if [ "${NOEMAP_FULL_PORTS:-0}" = "1" ] && [ -n "$_all_ports" ]; then
            printf '  %*s  ports: %s\n' "$_W_IP" '' "$_all_ports"
        fi
    done < "$_hosts_db"

    printf '\n'

    # Devices table (registered)
    if [ -f "$_devdb" ] && \
       awk -F'|' '/^[[:space:]]*$/{next}/^#/{next} NF>=2{found=1;exit} END{exit !found}' \
       "$_devdb" 2>/dev/null; then

        printf '  DEVICES\n\n'
        printf '  %-12s  %-16s  %-6s  %s\n' ALIAS IP PORT USER
        printf '  %s  %s  %s  %s\n' \
            "$(_pad 12)" "$(_pad 16)" "$(_pad 6)" "$(_pad 8)"
        awk -F'|' '
            /^[[:space:]]*$/ { next }
            /^#/             { next }
            NF >= 2 {
                port = ($4 == "" ? "22" : $4)
                user = ($3 == "" ? "?" : $3)
                printf "  %-12s  %-16s  %-6s  %s\n", $1, $2, port, user
            }
        ' "$_devdb"
        printf '\n'
    fi

    # CONNECT quick-reference — one block per registered device
    if [ -f "$_devdb" ] && \
       awk -F'|' '/^[[:space:]]*$/{next}/^#/{next} NF>=2{found=1;exit} END{exit !found}' \
       "$_devdb" 2>/dev/null; then

        printf '  CONNECT\n\n'

        while IFS='|' read -r _ca _cip _cuser _cport _rest; do
            case "$_ca" in ''|'#'*) continue ;; esac
            [ -n "$_ca" ] && [ -n "$_cip" ] || continue

            _cport="${_cport:-22}"

            _ctype=""
            if [ -f "$_hosts_db" ]; then
                _ctype="$(awk -F'|' -v ip="$_cip" '
                    /^[[:space:]]*$/ { next }
                    /^#/             { next }
                    $1 == ip         { print $2; exit }
                ' "$_hosts_db" 2>/dev/null)"
            fi

            case "$_ctype" in
                android-ssh) _suggest="getprop ro.product.model" ;;
                windows)     _suggest="ver" ;;
                router)      _suggest="cat /etc/openwrt_release 2>/dev/null || uname -a" ;;
                *)           _suggest="uname -a" ;;
            esac

            printf '  -- %s  (%s)  port %s --\n' "$_ca" "$_cip" "$_cport"
            printf '  shell        nssh %s\n'                    "$_ca"
            printf '  cmd          nssh %s %s\n'                 "$_ca" "$_suggest"
            printf '  copy from    nscp %s:/remote/path ./\n'   "$_ca"
            printf '  copy to      nscp ./file %s:/remote/\n'   "$_ca"
            printf '  sync to      nrsync ./dir/ %s:~/backup/\n' "$_ca"
            printf '  clipboard    nclip %s:/remote/file\n'      "$_ca"
            printf '\n'
        done < "$_devdb"
    fi
}

# ---------------------------------------------------------------------------
# prompt_new_hosts — called after render_output for IPs in hosts.db
# not yet in devices.db. Reads /dev/tty for alias and user.
# Skips silently in non-interactive environments.
# ---------------------------------------------------------------------------
prompt_new_hosts() {
    [ -t 1 ] || return 0

    _hosts_db="$BASE/state/hosts.db"
    _devdb="$BASE/state/devices.db"

    [ -f "$_hosts_db" ] && [ -s "$_hosts_db" ] || return 0
    [ -f "$_devdb" ] || touch "$_devdb"

    # Collect new hosts into a temp file (avoids subshell from pipe)
    _new_tmp="$(mktemp "${TMPDIR:-/tmp}/noemap.XXXXXX")"
    while IFS='|' read -r _ip _type _ttl _ssh_port _all_ports; do
        [ -n "$_ip" ] || continue
        _found="$(awk -F'|' -v ip="$_ip" '
            /^[[:space:]]*$/ { next }
            /^#/             { next }
            $2 == ip         { print 1; exit }
        ' "$_devdb" 2>/dev/null)"
        [ -z "$_found" ] && printf '%s|%s|%s\n' "$_ip" "$_type" "${_ssh_port:-22}" >> "$_new_tmp"
    done < "$_hosts_db"

    [ -s "$_new_tmp" ] || { rm -f "$_new_tmp"; return 0; }

    printf '  -- NEW HOSTS -- press Enter to accept suggestion --\n\n'

    while IFS='|' read -r _ip _type _ssh_port; do
        [ -n "$_ip" ] || continue

        printf '  %s  type=%-12s  port=%s\n' "$_ip" "$_type" "${_ssh_port:-22}"

        # Default alias suggestion: d0, d1, d2 …
        _n=0
        _default_alias="d${_n}"
        while awk -F'|' -v a="$_default_alias" '
            /^[[:space:]]*$/{next} /^#/{next}
            $1==a{found=1;exit} END{exit !found}
        ' "$_devdb" 2>/dev/null; do
            _n=$(( _n + 1 ))
            _default_alias="d${_n}"
        done

        # Alias prompt (loop until valid or Enter for default)
        _alias=""
        while [ -z "$_alias" ]; do
            printf '  Alias [%s]: ' "$_default_alias"
            read -r _input_alias </dev/tty || _input_alias=""
            _input_alias="$(printf '%s' "$_input_alias" | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

            if [ -z "$_input_alias" ]; then
                _alias="$_default_alias"
            else
                case "$_input_alias" in
                    *[^a-zA-Z0-9_-]*)
                        printf '  [!] invalid chars -- only a-z 0-9 _ -\n'
                        continue ;;
                esac
                if [ "${#_input_alias}" -gt 20 ]; then
                    printf '  [!] too long (max 20 chars)\n'
                    continue
                fi
                _alias="$_input_alias"
            fi
        done

        # If alias taken by a different IP → update that entry's IP
        _alias_cur_ip="$(awk -F'|' -v a="$_alias" '
            /^[[:space:]]*$/ { next }
            /^#/             { next }
            $1 == a          { print $2; exit }
        ' "$_devdb" 2>/dev/null)"

        if [ -n "$_alias_cur_ip" ] && [ "$_alias_cur_ip" != "$_ip" ]; then
            printf '  [i] "%s" existed (%s) -- IP updated to %s\n' \
                "$_alias" "$_alias_cur_ip" "$_ip"
            known_hosts_remove_ip "$_alias_cur_ip"
            _tmp_db="$(mktemp "${TMPDIR:-/tmp}/ndevs.XXXXXX")"
            awk -F'|' -v a="$_alias" -v ni="$_ip" -v np="${_ssh_port:-22}" '
                /^[[:space:]]*$/ { print; next }
                /^#/             { print; next }
                $1 == a          { printf "%s|%s|%s|%s\n", $1, ni, $3, np; next }
                { print }
            ' "$_devdb" > "$_tmp_db"
            mv -f "$_tmp_db" "$_devdb"
            printf '\n'
            continue
        fi

        # User prompt — default suggestion is lowercase system username
        _default_user="$(id -un 2>/dev/null | tr '[:upper:]' '[:lower:]' || printf 'user')"
        _reg_user=""
        while [ -z "$_reg_user" ]; do
            printf '  User [%s]: ' "$_default_user"
            read -r _input_user </dev/tty || _input_user=""
            _input_user="$(printf '%s' "$_input_user" | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
            if [ -z "$_input_user" ]; then
                _reg_user="$_default_user"
            else
                _reg_user="$_input_user"
            fi
        done

        known_hosts_remove_ip "$_ip"

        _tmp_db="$(mktemp "${TMPDIR:-/tmp}/ndevs.XXXXXX")"
        {
            cat "$_devdb"
            printf '%s|%s|%s|%s\n' "$_alias" "$_ip" "$_reg_user" "${_ssh_port:-22}"
        } > "$_tmp_db"

        if awk -F'|' '
            /^[[:space:]]*$/ { next }
            /^#/             { next }
            NF < 2           { exit 1 }
        ' "$_tmp_db"; then
            mv -f "$_tmp_db" "$_devdb"
            printf '  [OK] registered "%s" -> %s  user=%s  port=%s\n\n' \
                "$_alias" "$_ip" "$_reg_user" "${_ssh_port:-22}"
        else
            rm -f "$_tmp_db"
            printf '  [!] validation failed for "%s" -- skipped\n\n' "$_alias"
        fi

    done < "$_new_tmp"

    rm -f "$_new_tmp"
}
