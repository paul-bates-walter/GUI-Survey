if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/_sdl-env.sh"

MODE="${1:-release}"
cd "$ROOT_DIR"
case "$MODE" in
  release) zig build -Doptimize=ReleaseFast ;;
  debug)   zig build ;;
  *) echo "Unsupported mode: $MODE (use debug or release)" >&2; exit 1 ;;
esac
echo "Built ($MODE) into: $ROOT_DIR/zig-out"
