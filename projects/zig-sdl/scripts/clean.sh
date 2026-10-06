if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

rm -rf "$ROOT_DIR/zig-out" "$ROOT_DIR/.zig-cache" "$ROOT_DIR/zig-cache" "$ROOT_DIR/build"
echo "Cleaned."
