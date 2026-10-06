if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/_sdl-env.sh"

if [[ ! -x "$ROOT_DIR/zig-out/bin/png-editor-sdl-zig" ]]; then
  bash "$SCRIPT_DIR/build.sh" debug
fi
exec "$ROOT_DIR/zig-out/bin/png-editor-sdl-zig"
