#!/usr/bin/env bash
set -euo pipefail

if [[ "${CLAWDBOT_USE_OPENCODE:-false}" == "true" ]]; then
  if [[ -d "/opt/default-opencode" ]]; then
    if [[ ! -d "/home/node/.config/opencode" ]]; then
      mkdir -p "/home/node/.config"
      cp -a "/opt/default-opencode" "/home/node/.config/opencode"
      chown -R 1000:1000 "/home/node/.config/opencode" || true
    fi
  else
    echo "[clawdbot] warning: CLAWDBOT_USE_OPENCODE=true but /opt/default-opencode is missing" >&2
  fi
fi

exec "$@"
