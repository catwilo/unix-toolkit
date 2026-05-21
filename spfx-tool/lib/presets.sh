#!/usr/bin/env bash
# lib/presets.sh — Declarative scaffolding presets for SPFx project types.
# Replaces interactive `yo @microsoft/sharepoint` with versioned, reproducible configs.
# shellcheck shell=bash

if [[ "${_SPFX_PRESETS_LOADED:-}" == "1" ]]; then return 0; fi
_SPFX_PRESETS_LOADED=1

# shellcheck source=lib/core.sh
source "${SPFX_DIR}/lib/core.sh"
# shellcheck source=lib/runtime.sh
source "${SPFX_DIR}/lib/runtime.sh"

# ── Preset registry ───────────────────────────────────────────────────────────
SPFX_PRESET_TYPES=(react-webpart extension library ace interactive)

validate_preset() {
    local t="${1:-}"
    printf '%s\n' "${SPFX_PRESET_TYPES[@]}" | grep -qx "$t" \
        || log_die "Unknown preset: '$t'. Valid: ${SPFX_PRESET_TYPES[*]}"
}

# scaffold_project <name> <preset_type>
scaffold_project() {
    local name="${1:?scaffold_project: name required}"
    local preset="${2:-interactive}"
    validate_project_name "$name"

    local pdir="${SPFX_DIR}/projects/${name}"
    mkdir -p "$pdir"

    if [[ "$preset" == "interactive" ]]; then
        log_info "Launching interactive Yeoman generator..."
        # Normalize workspace ownership to u:u before yo writes into /workspace.
        # Without this, host uid ≠ 1000 leaves /workspace owned by another uid
        # and yo (running as user u) fails with EACCES on first write.
        podman_exec_root "$name" "chown -R u:u /workspace"
        run_exec "$name" "yo @microsoft/sharepoint"
        return
    fi

    scaffold_from_config "$name" "$preset"
}

# scaffold_from_config <name> <preset>
# Non-interactive path for CI — uses @microsoft/generator-sharepoint --configFile.
# The preset JSON is template-substituted (__PROJECT_NAME__ → name) into a
# temp file, then mounted read-only — no host path leaks into the container.
scaffold_from_config() {
    local name="${1:?}"
    local preset="${2:?}"
    validate_project_name "$name"
    validate_preset "$preset"

    local pdir="${SPFX_DIR}/projects/${name}"
    mkdir -p "$pdir"

    local config_file="${SPFX_DIR}/lib/presets/${preset}.json"
    [[ -f "$config_file" ]] || log_die "Preset config missing: $config_file"

    spfx_load_versions

    # Substitute __PROJECT_NAME__ into a temp file. validate_project_name already
    # restricts $name to [a-zA-Z][a-zA-Z0-9_-]*, which is safe for sed (no /, &, \).
    local rendered_cfg
    rendered_cfg="$(make_tmpfile "spfx-preset" ".json")"
    register_tmpfile "$rendered_cfg"
    sed "s/__PROJECT_NAME__/${name}/g" "$config_file" > "$rendered_cfg"

    # Sanity check: the placeholder must not survive.
    if grep -q '__PROJECT_NAME__' "$rendered_cfg"; then
        log_die "Preset substitution failed — placeholder remains in: $rendered_cfg"
    fi

    # Normalize workspace ownership so user u (uid 1000) can write to /workspace.
    podman_exec_root "$name" "chown -R u:u /workspace"

    # Mount the rendered preset at a fixed container path — avoids any host /tmp path leak.
    local container_cfg="/tmp/spfx-preset.json"

    _podman_run \
        --user u \
        --volume "${pdir}:/workspace:z" \
        --volume "${rendered_cfg}:${container_cfg}:ro,z" \
        --workdir /workspace \
        "$PODMAN_IMAGE" \
        bash --noprofile --norc -c "
            yo @microsoft/sharepoint \
                --force \
                --skip-install \
                --no-insight \
                --output /workspace \
                --configFile '${container_cfg}'
        "
    log_ok "Non-interactive scaffold complete: $pdir"
}
