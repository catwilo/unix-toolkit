#!/usr/bin/env bash
# byobu-status.sh — aicli status plugin for byobu status bar
# Install: copy to ~/.config/byobu/aicli_status.sh and add to byobu status config

SOCK="/tmp/aicli/orchestrator.sock"
SESS_FILE="/tmp/aicli/current_session"

if [[ ! -S "${SOCK}" ]]; then
  echo " [aicli: offline]"
  exit 0
fi

# Read current session info
SESSION_ID=""
[[ -f "${SESS_FILE}" ]] && SESSION_ID="$(cat "${SESS_FILE}" 2>/dev/null)"

# Query orchestrator for status (timeout 500ms)
STATUS=$(echo '{"cmd":"status"}' | socat -t0.5 - "UNIX-CONNECT:${SOCK}" 2>/dev/null || true)

if [[ -z "${STATUS}" ]]; then
  echo " [aicli: no response]"
  exit 0
fi

# Parse active session count (simple grep, no jq dependency)
COUNT=$(echo "${STATUS}" | grep -o '"active_sessions":[0-9]*' | grep -o '[0-9]*' || echo "0")

# Read sentinel for token pressure indicator
SENTINEL_SOCK="/tmp/aicli/sentinel.sock"
PRESSURE=""
if [[ -S "${SENTINEL_SOCK}" ]]; then
  SENTINEL=$(echo '{"cmd":"status"}' | socat -t0.5 - "UNIX-CONNECT:${SENTINEL_SOCK}" 2>/dev/null || true)
  AVAIL=$(echo "${SENTINEL}" | grep -o '"ram_available_mb":[0-9]*' | grep -o '[0-9]*' || echo "")
  [[ -n "${AVAIL}" && "${AVAIL}" -lt 500 ]] && PRESSURE=" ⚠"
fi

echo " [aicli: ${COUNT} sess${PRESSURE}]"
