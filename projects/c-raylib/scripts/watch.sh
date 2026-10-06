if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT_DIR/src"

if ! command -v inotifywait >/dev/null 2>&1; then
  echo "inotify-tools is required (apt install inotify-tools)" >&2
  exit 1
fi

echo "Watching $SRC_DIR — rebuild + relaunch on change (no in-process reload for C)."
bash "$SCRIPT_DIR/build.sh"
"$ROOT_DIR/build/linux/png-editor-raylib" &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT

while inotifywait -e modify,create,delete,move "$SRC_DIR" --include '.*\.[ch]$' >/dev/null 2>&1; do
  if bash "$SCRIPT_DIR/build.sh"; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    "$ROOT_DIR/build/linux/png-editor-raylib" &
    APP_PID=$!
    echo "↻ relaunched"
  else
    echo "✗ build failed; keeping previous app running"
  fi
done
