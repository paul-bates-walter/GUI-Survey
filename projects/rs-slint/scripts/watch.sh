#!/usr/bin/env bash
# Genuine hot reload (spec.md "Hot Swapping"): rebuild ONLY the app dylib
# (src/lib.rs + ui/app.slint -> target/debug/libpng_editor_slint.so) on every
# source change. The running app (started separately with scripts/run.sh) polls
# that .so and, when it changes, reloads it and re-wires the window's callbacks
# in place — the window, the current picture, the selected tool and the metadata
# form are all preserved. Nothing is relaunched.
#
# Usage: run the app in one terminal (scripts/run.sh) and this watcher in
# another. Edit src/*.rs (or ui/app.slint), save, and the change appears in the
# running app.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT_DIR/src"
UI_DIR="$ROOT_DIR/ui"
[[ -s "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

echo "Watching $SRC_DIR and $UI_DIR — rebuilding the hot-reload dylib on change."
echo "Start the app in another terminal with scripts/run.sh to see edits live."

build_lib() {
  # --lib builds only libpng_editor_slint.{so,dylib,dll} (build.rs recompiles the
  # .slint UI); the host binary is left running. A failed build keeps the last
  # good dylib.
  if cargo build --lib --manifest-path "$ROOT_DIR/Cargo.toml"; then
    echo "↻ dylib rebuilt — the running app will swap it in"
  else
    echo "✗ build failed; the app keeps the previous code"
  fi
}

# Preferred: cargo-watch drives incremental library rebuilds in one process.
if cargo watch --version >/dev/null 2>&1; then
  exec cargo watch -w "$SRC_DIR" -w "$UI_DIR" -w "$ROOT_DIR/Cargo.toml" \
    -x "build --lib --manifest-path $ROOT_DIR/Cargo.toml"
fi

# Fallback: inotify (or a polling loop) that rebuilds the dylib on change.
build_lib
if command -v inotifywait >/dev/null 2>&1; then
  while inotifywait -r -e modify,create,delete,move --include '.*\.(rs|slint)$' "$SRC_DIR" "$UI_DIR" >/dev/null 2>&1; do
    echo "↻ change detected, rebuilding dylib..."
    build_lib
  done
else
  echo "inotify-tools not found; install it or cargo-watch for live reload." >&2
  exit 1
fi
