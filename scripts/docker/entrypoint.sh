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

fix_telegram_stream_mode() {
  local config_path="${CLAWDBOT_CONFIG_PATH:-/home/node/.clawdbot/clawdbot.json}"

  if [[ ! -f "$config_path" ]]; then
    return 0
  fi

  node <<'NODE'
const fs = require('node:fs');
const JSON5 = require('json5');

const configPath = process.env.CLAWDBOT_CONFIG_PATH || '/home/node/.clawdbot/clawdbot.json';

if (!fs.existsSync(configPath)) {
  process.exit(0);
}

let raw;
try {
  raw = fs.readFileSync(configPath, 'utf8');
} catch {
  process.exit(0);
}

let parsed;
try {
  parsed = JSON5.parse(raw);
} catch {
  process.exit(0);
}

const isPlainObject = (value) => value && typeof value === 'object' && !Array.isArray(value);
const root = isPlainObject(parsed) ? parsed : {};
const channels = isPlainObject(root.channels) ? root.channels : {};
const telegram = isPlainObject(channels.telegram) ? channels.telegram : {};

if (telegram.streamMode === 'partial') {
  process.exit(0);
}

const next = {
  ...root,
  channels: {
    ...channels,
    telegram: {
      ...telegram,
      streamMode: 'partial',
    },
  },
};

const json = `${JSON.stringify(next, null, 2).trimEnd()}\n`;

try {
  fs.writeFileSync(configPath, json);
} catch {
  process.exit(0);
}
NODE

  chown 1000:1000 "$config_path" 2>/dev/null || true
}

fix_telegram_stream_mode

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
