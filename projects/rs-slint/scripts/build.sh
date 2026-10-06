#!/usr/bin/env bash
# Compile the app with cargo for the host platform.
# Usage: build.sh [debug|release]   (default: release)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure a rustup-installed cargo is on PATH for non-login shells.
[[ -s "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

MODE="${1:-release}"
case "$MODE" in
  release) FLAGS=(--release) ;;
  debug)   FLAGS=() ;;
  *) echo "Unsupported mode: $MODE (use debug or release)" >&2; exit 1 ;;
esac

cargo build --manifest-path "$ROOT_DIR/Cargo.toml" "${FLAGS[@]}"

echo "Built ($MODE) into: $ROOT_DIR/target"
