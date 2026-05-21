#!/usr/bin/env bash
# lib/runtime.sh — Podman rootless execution abstraction.
# All container invocations go through run_exec / run_query / run_shell.
# Never call podman directly from command scripts.
# shellcheck shell=bash

if [[ "${_SPFX_RUNTIME_LOADED:-}" == "1" ]]; then return 0; fi
_SPFX_RUNTIME_LOADED=1

# shellcheck source=lib/core.sh
source "${SPFX_DIR}/lib/core.sh"

# ── Podman rootless ───────────────────────────────────────────────────────────

# Named volume that holds the global npm prefix (yo + generator).
_PODMAN_TOOLS_VOLUME="spfx-global-tools"
# Mount point inside the container for the global tools volume.
_PODMAN_TOOLS_MNT="/usr/local/lib/node_modules_global"
# Bin directory inside the volume — npm puts executables here when prefix is set.
_PODMAN_TOOLS_BIN="${_PODMAN_TOOLS_MNT}/bin"

# _podman_run <extra podman flags...> <image> <cmd...>
# Single source of truth for all podman invocations.
# Callers are responsible for --user (u for normal ops, root for install/chown).
_podman_run() {
    local -a extra_args=("$@")
    podman run \
        --rm \
        --network=host \
        --security-opt=no-new-privileges \
        --volume "${SPFX_DIR}/lib/resolv.conf:/etc/resolv.conf:ro,z" \
        --volume "${_PODMAN_TOOLS_VOLUME}:${_PODMAN_TOOLS_MNT}:z" \
        --env "PATH=${_PODMAN_TOOLS_BIN}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        --env "NPM_CONFIG_PREFIX=${_PODMAN_TOOLS_MNT}" \
        --env "npm_config_cache=/home/u/.npm" \
        "${extra_args[@]}"
}

# podman_ensure_base_image
# Pulls the pinned base image if not already present.
podman_ensure_base_image() {
    spfx_load_versions
    if ! podman image exists "$PODMAN_BASE_IMAGE" 2>/dev/null; then
        log_info "Pulling ${PODMAN_BASE_IMAGE}..."
        podman pull "$PODMAN_BASE_IMAGE"
        log_ok "Base image ready: ${PODMAN_BASE_IMAGE}"
    else
        log_ok "Base image already present: ${PODMAN_BASE_IMAGE}"
    fi
}

# podman_ensure_image — checks for the built dev image
podman_ensure_image() {
    spfx_load_versions
    if ! podman image exists "$PODMAN_IMAGE" 2>/dev/null; then
        log_die "Dev image not found: ${PODMAN_IMAGE}. Run: spfx-bootstrap"
    fi
    log_ok "Image ready: ${PODMAN_IMAGE}"
}

# podman_build_image
# Builds localhost/spfx-dev:latest from lib/Containerfile using the base image.
podman_build_image() {
    spfx_load_versions
    log_info "Building ${PODMAN_IMAGE} (base: ${PODMAN_BASE_IMAGE})..."
    # Build context is SPFX_DIR (not lib/) so the Containerfile can COPY
    # both lib/ and fixtures/ — needed for npm cache warming during build.
    # --dns: build RUN layers use slirp4netns (not host network), so DNS must
    # be set explicitly here; the resolv.conf volume mount only applies at runtime.
    podman build \
        --tag "$PODMAN_IMAGE" \
        --build-arg "BASE_IMAGE=${PODMAN_BASE_IMAGE}" \
        --dns 1.1.1.1 \
        --file "${SPFX_DIR}/lib/Containerfile" \
        "${SPFX_DIR}" \
        2>&1 | tee -a "${LOG_FILE:-/dev/null}"
    log_ok "Image built: ${PODMAN_IMAGE}"
}

# podman_exec <project_or_empty> <script_body>
# Runs a bash script inside the container as user u.
# project → mounts SPFX_DIR/projects/<project> to /workspace.
# ./node_modules/.bin is prepended to PATH so project-local binaries
# (heft, gulp, …) are resolved without requiring a global install.
podman_exec() {
    local project="${1:-}"
    local body="${2:?podman_exec: script body required}"
    spfx_load_versions

    local -a vol_args=()
    local -a work_args=()
    if [[ -n "$project" ]]; then
        local pdir="${SPFX_DIR}/projects/${project}"
        [[ -d "$pdir" ]] || log_die "podman_exec: project not found: $pdir"
        vol_args+=(--volume "${pdir}:/workspace:z")
        work_args+=(--workdir /workspace)
    fi

    _podman_run \
        --user u \
        "${vol_args[@]}" \
        "${work_args[@]}" \
        "$PODMAN_IMAGE" \
        bash --noprofile --norc -c 'export PATH="./node_modules/.bin:${PATH}"; '"$body"
}

# podman_exec_root <project> <script_body>
# Runs a bash script inside the container as root.
# Used exclusively for chown / permission normalization before npm ops.
podman_exec_root() {
    local project="${1:-}"
    local body="${2:?podman_exec_root: script body required}"
    spfx_load_versions

    local -a vol_args=()
    local -a work_args=()
    if [[ -n "$project" ]]; then
        local pdir="${SPFX_DIR}/projects/${project}"
        [[ -d "$pdir" ]] || log_die "podman_exec_root: project not found: $pdir"
        vol_args+=(--volume "${pdir}:/workspace:z")
        work_args+=(--workdir /workspace)
    fi

    _podman_run \
        --user root \
        "${vol_args[@]}" \
        "${work_args[@]}" \
        "$PODMAN_IMAGE" \
        bash --noprofile --norc -c "$body"
}

# podman_query <project_or_empty> <one-liner>
podman_query() {
    local project="${1:-}"
    local body="${2:?podman_query: body required}"
    podman_exec "$project" "$body" 2>/dev/null
}

# podman_dev <project> <host> <port>
# Interactive dev server — runs as user u.
# ~/.rushstack is mounted to /home/u/.rushstack for TLS cert caching.
podman_dev() {
    local project="${1:?podman_dev: project required}"
    local host="${2:?podman_dev: host required}"
    local port="${3:?podman_dev: port required}"
    spfx_load_versions

    local pdir="${SPFX_DIR}/projects/${project}"
    [[ -d "$pdir" ]] || log_die "podman_dev: project not found: $pdir"

    mkdir -p "$HOME/.rushstack"

    _podman_run \
        --user u \
        --interactive --tty \
        --volume "${pdir}:/workspace:z" \
        --volume "${HOME}/.rushstack:/home/u/.rushstack:z" \
        --workdir /workspace \
        --env "HEFT_SERVE_HOST=${host}" \
        --env "HEFT_SERVE_PORT=${port}" \
        "$PODMAN_IMAGE" \
        bash --noprofile --norc -c "npm exec --no -- heft start --allow-warnings"
}

# podman_shell <project_or_empty>
# Interactive bash shell as user u.
podman_shell() {
    local project="${1:-}"
    spfx_load_versions

    local -a vol_args=()
    local -a work_args=(--workdir /home/u)
    if [[ -n "$project" ]]; then
        local pdir="${SPFX_DIR}/projects/${project}"
        [[ -d "$pdir" ]] || log_die "podman_shell: project not found: $pdir"
        vol_args+=(--volume "${pdir}:/workspace:z")
        work_args=(--workdir /workspace)
    fi

    _podman_run \
        --user u \
        --interactive --tty \
        "${vol_args[@]}" \
        "${work_args[@]}" \
        "$PODMAN_IMAGE" \
        bash --login
}

# ── Unified API ───────────────────────────────────────────────────────────────

run_exec()  { podman_exec  "$@"; }
run_query() { podman_query "$@"; }
run_shell() { podman_shell "$@"; }

# ── Shared helpers ────────────────────────────────────────────────────────────

# needs_install <project>
# True if node_modules is missing or stale relative to lockfile.
needs_install() {
    local pdir="${SPFX_DIR}/projects/${1:?}"
    [[ -d "$pdir/node_modules" ]]      || return 0
    [[ -f "$pdir/package-lock.json" ]] || return 0
    if [[ "$pdir/package-lock.json" -nt "$pdir/node_modules" ]]; then return 0; fi
    return 1
}

# install_deps <project>
# Normalizes /workspace ownership to u:u (root pass) before npm ci to prevent
# EACCES on package-lock.json when scaffold was seeded by a different UID.
install_deps() {
    local project="${1:?install_deps: project required}"
    log_info "Normalizing workspace ownership..."
    podman_exec_root "$project" "chown -R u:u /workspace"
    log_info "Installing dependencies..."
    if ! run_exec "$project" '
        if [[ -f package.json ]]; then
            if [[ -f package-lock.json ]]; then
                npm ci --prefer-offline --no-fund
            else
                npm install --no-fund
            fi
        else
            echo "  ✘  install: package.json not found in /workspace" >&2
            exit 1
        fi
        # post-install assertion: heft must be resolvable by npm. heft arrives as
        # a transitive dep of @microsoft/spfx-web-build-rig, so it is NOT linked
        # into node_modules/.bin and `command -v heft` will fail — that is
        # expected. We instead confirm the package resolves and that the project
        # exposes a build script (fixtures define build:ship; generator-made
        # projects may instead define build/bundle — accept any of them).
        if ! node -e "require.resolve(\"@rushstack/heft/package.json\")" >/dev/null 2>&1; then
            echo "  ✘  post-install: @rushstack/heft not resolvable in node_modules" >&2
            exit 1
        fi
        if ! npm run 2>/dev/null | grep -qE "build:ship|^  build$|^  bundle$"; then
            echo "  ✘  post-install: package.json defines no build/bundle/build:ship script" >&2
            exit 1
        fi
    '; then
        log_die "Dependency installation failed for: ${project}"
    fi
    log_ok "Dependencies installed: ${project}"
}

# detect_pipeline <project>
# Prints "heft" or "hybrid".
#   heft   → heft-only project (config/heft.json present, no gulpfile.js). Build
#            is driven entirely by heft; produces compiled output under lib/.
#   hybrid → legacy gulp-on-heft project (gulpfile.js present). Build runs the
#            gulp ship tasks, which produce a .sppkg under sharepoint/solution/.
detect_pipeline() {
    local pdir="${SPFX_DIR}/projects/${1:?}"
    if [[ -f "$pdir/config/heft.json" && ! -f "$pdir/gulpfile.js" ]]; then
        echo "heft"
    else
        echo "hybrid"
    fi
}

# build_command <pipeline>
# Prints the canonical production build command for a pipeline.
#
# Rationale: in npm 7+ the bins of *transitive* dependencies are NOT linked into
# the root node_modules/.bin. @rushstack/heft arrives transitively via
# @microsoft/spfx-web-build-rig, so `heft ...` is not on PATH and bare invocation
# fails with "heft: command not found". The robust, install-free way to run it is
# to go through the project's own npm scripts (defined in each fixture's
# package.json), which npm resolves by walking the full module tree. We pass
# `--` so npm forwards no extra args and runs the script verbatim.
build_command() {
    local pipeline="${1:?build_command: pipeline required}"
    if [[ "$pipeline" == "heft" ]]; then
        # Heft-only fixtures define: "build:ship": "heft build --clean --production"
        echo 'npm run build:ship'
    else
        # Gulp pipeline (generator-made projects with a gulpfile.js). gulp is a
        # direct dependency so `npm exec` resolves its bin without a global
        # install. We invoke the ship tasks directly rather than via a named npm
        # script, because generator-made projects do not all define build:ship.
        echo 'npm exec --no -- gulp bundle --ship && npm exec --no -- gulp package-solution --ship'
    fi
}
