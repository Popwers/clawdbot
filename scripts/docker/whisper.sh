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

if [[ ! -f "$model_path" ]]; then
  echo "[clawdbot] whisper: missing model $model_path" >&2
  echo "[clawdbot] whisper: set CLAWDBOT_WHISPER_MODEL or enable preload" >&2
  exit 1
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
