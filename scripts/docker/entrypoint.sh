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

preload_whisper() {
  local model="${CLAWDBOT_WHISPER_MODEL:-base}"
  local preload="${CLAWDBOT_WHISPER_PRELOAD:-true}"
  local cache_home="${XDG_CACHE_HOME:-/opt/whisper-cache}"
  local cache_dir="${cache_home%/}/whisper"

  if [[ "$preload" != "true" ]]; then
    return 0
  fi

  mkdir -p "$cache_dir"
  chown -R 1000:1000 "$cache_home" 2>/dev/null || true

  if [[ -f "$cache_dir/${model}.pt" || -f "$cache_dir/${model}.en.pt" ]]; then
    return 0
  fi

  echo "[clawdbot] whisper: preloading model '$model' into $cache_dir" >&2
  python3 - <<PY || echo "[clawdbot] whisper: preload failed (will download on first use)" >&2
import os
import whisper
model = os.environ.get("CLAWDBOT_WHISPER_MODEL", "base")
whisper.load_model(model)
PY
}

preload_whisper

exec "$@"
