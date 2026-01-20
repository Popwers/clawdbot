#!/usr/bin/env bash
set -euo pipefail

if [[ "${CLAWDBOT_USE_OPENCODE:-false}" == "true" ]]; then
  if [[ -d "/opt/default-opencode" ]]; then
    mkdir -p "/home/node/.config"
    # Always sync from default config to ensure fresh deployments match dotfiles
    rm -rf "/home/node/.config/opencode"
    cp -a "/opt/default-opencode" "/home/node/.config/opencode"
    chown -R 1000:1000 "/home/node/.config/opencode" || true
    echo "[clawdbot] OpenCode config synced from /opt/default-opencode" >&2
  else
    echo "[clawdbot] warning: CLAWDBOT_USE_OPENCODE=true but /opt/default-opencode is missing" >&2
  fi
fi

preload_whisper() {
  local model="${CLAWDBOT_WHISPER_MODEL:-base}"
  local preload="${CLAWDBOT_WHISPER_PRELOAD:-true}"
  local cache_home="${XDG_CACHE_HOME:-/opt/whisper-cache}"
  local cache_dir="${cache_home%/}/whisper.cpp"
  local model_path="$cache_dir/ggml-${model}.bin"

  if [[ "$preload" != "true" ]]; then
    return 0
  fi

  mkdir -p "$cache_dir"
  chown -R 1000:1000 "$cache_home" 2>/dev/null || true

  if [[ -f "$model_path" ]]; then
    return 0
  fi

  echo "[clawdbot] whisper.cpp: downloading model '${model}' into $model_path" >&2

  # Official model URLs are hosted by the whisper.cpp project.
  local url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${model_path##*/}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$model_path" "$url" || true
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$model_path" "$url" || true
  fi

  if [[ ! -f "$model_path" ]]; then
    echo "[clawdbot] whisper.cpp: preload failed (will download on demand when transcription runs)" >&2
    return 0
  fi

  chmod a+r "$model_path" 2>/dev/null || true
}

preload_whisper

exec "$@"
