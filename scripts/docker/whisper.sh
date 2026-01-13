#!/usr/bin/env bash
set -euo pipefail

# Minimal compatibility wrapper so Clawdbot can call `whisper` and receive a
# plain transcript on stdout.
#
# Supported (best-effort):
# - whisper <audio>
# - whisper --model base <audio>
# - whisper --model base --language fr <audio>
# - whisper --task translate ... (ignored for now; whisper.cpp supports it but
#   this wrapper keeps output stable for Clawdbot)

model="base"
language=""
audio=""

args=("$@")
idx=0
while [[ $idx -lt ${#args[@]} ]]; do
  a="${args[$idx]}"
  case "$a" in
    --model|-m)
      idx=$((idx+1))
      model="${args[$idx]:-}"
      ;;
    --language|--lang|-l)
      idx=$((idx+1))
      language="${args[$idx]:-}"
      ;;
    --task)
      idx=$((idx+1))
      # accepted but currently ignored
      ;;
    --output_format|--output_dir|--fp16|--verbose)
      # accepted but ignored
      idx=$((idx+1))
      ;;
    --help|-h)
      exec /usr/local/bin/whisper-cli -h
      ;;
    --*)
      # ignore unknown flags to keep the wrapper permissive
      ;;
    *)
      if [[ -z "$audio" ]]; then
        audio="$a"
      fi
      ;;
  esac
  idx=$((idx+1))
done

if [[ -z "$audio" ]]; then
  echo "usage: whisper [--model <name>] [--language <code>] <audio>" >&2
  exit 2
fi

cache_home="${XDG_CACHE_HOME:-/opt/whisper-cache}"
model_dir="${cache_home%/}/whisper.cpp"
model_file="ggml-${model}.bin"
model_path="$model_dir/$model_file"

download_model() {
  mkdir -p "$model_dir"

  # Prevent concurrent downloads (multiple messages / multiple workers).
  local lock_dir="$model_dir/.download.lock"
  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 0.2
  done
  trap 'rmdir "$lock_dir" 2>/dev/null || true' RETURN

  if [[ -f "$model_path" ]]; then
    return 0
  fi

  local url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${model_file}"
  echo "[clawdbot] whisper.cpp: downloading model '${model}'" >&2

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$model_path" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$model_path" "$url"
  else
    echo "[clawdbot] whisper.cpp: missing curl/wget; cannot download model" >&2
    return 1
  fi

  chmod a+r "$model_path" 2>/dev/null || true
}

if [[ ! -f "$model_path" ]]; then
  echo "[clawdbot] whisper.cpp: model missing (${model_file}); downloading on demand" >&2
  if ! download_model; then
    echo "[clawdbot] whisper.cpp: download failed; set CLAWDBOT_WHISPER_MODEL or enable preload" >&2
    exit 1
  fi
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
out_prefix="$tmp_dir/out"

cli_args=(
  "--model" "$model_path"
  "--file" "$audio"
  "-otxt"
  "-of" "$out_prefix"
)

if [[ -n "$language" ]]; then
  cli_args+=("--language" "$language")
fi

/usr/local/bin/whisper-cli "${cli_args[@]}" >/dev/null

cat "${out_prefix}.txt"
