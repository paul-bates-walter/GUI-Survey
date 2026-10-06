if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BIN="$ROOT_DIR/build/linux/png-editor-raylib"
if [[ "$(uname -s)" == "Darwin" ]]; then
  BIN="$ROOT_DIR/build/macos/png-editor-raylib"
fi
if [[ ! -x "$BIN" ]]; then
  bash "$SCRIPT_DIR/build.sh"
fi
exec "$BIN"
