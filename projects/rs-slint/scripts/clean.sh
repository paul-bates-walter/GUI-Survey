#!/usr/bin/env bash
# Remove build artifacts.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
[[ -s "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

cargo clean --manifest-path "$ROOT_DIR/Cargo.toml" 2>/dev/null || rm -rf "$ROOT_DIR/target"
rm -rf "$ROOT_DIR/build"
echo "Cleaned."
