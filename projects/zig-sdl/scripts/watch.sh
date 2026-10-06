if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT_DIR/src"
. "$SCRIPT_DIR/_sdl-env.sh"

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "inotify-tools is required (apt install inotify-tools)" >&2
  exit 1
fi

echo "Watching $SRC_DIR — rebuild + relaunch on change (no in-process reload for zig)."
bash "$SCRIPT_DIR/build.sh" debug
"$ROOT_DIR/zig-out/bin/png-editor-sdl-zig" &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT

while inotifywait -r -e modify,create,delete,move --include '.*\.zig$' "$SRC_DIR" >/dev/null 2>&1; do
  if bash "$SCRIPT_DIR/build.sh" debug; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    "$ROOT_DIR/zig-out/bin/png-editor-sdl-zig" &
    APP_PID=$!
    echo "↻ relaunched"
  else
    echo "✗ build failed; keeping previous app running"
  fi
done
