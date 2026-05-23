#!/usr/bin/env bash
# build-all.sh — builds all aicli container images in parallel
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

build() {
  local name="$1" ctx="$2"
  echo "[${name}] building..."
  podman build -t "localhost/${name}:latest" -f "${ctx}/Containerfile" "${ctx}" \
    && echo "[${name}] ✓ done" \
    || echo "[${name}] ✗ FAILED"
}

export -f build

# Build stateless services in parallel, browser-worker sequentially last (heaviest)
parallel_builds=(
  "aicli-sentinel::${REPO_ROOT}/containers/sentinel"
  "aicli-orchestrator::${REPO_ROOT}/containers/orchestrator"
  "aicli-memory-engine::${REPO_ROOT}/containers/memory-engine"
  "aicli-compressor::${REPO_ROOT}/containers/compressor"
)

pids=()
for entry in "${parallel_builds[@]}"; do
  name="${entry%%::*}"
  ctx="${entry##*::}"
  build "$name" "$ctx" &
  pids+=($!)
done

# Wait for all parallel builds
for pid in "${pids[@]}"; do
  wait "$pid"
done

# Build browser-worker last (downloads ~600MB Chrome, benefit from layer cache)
build "aicli-browser-worker" "${REPO_ROOT}/containers/browser-worker"

echo ""
echo "All images built. Verify with: podman images | grep aicli"
