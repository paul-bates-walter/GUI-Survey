if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi

set -euo pipefail

APP_NAME="png-editor-raylib"
SCRIPT_DIR="$(realpath $(dirname "${BASH_SOURCE[0]}"))"
ROOT_DIR="$(realpath "${SCRIPT_DIR}/..")"
TARGET="${1:-host}"
MODE="${MODE:-release}"

if [ "$TARGET" = "host" ]; then
  case "$(uname -s)" in
    Linux) TARGET="linux" ;;
    Darwin) TARGET="macos" ;;
    *) echo "Unsupported host OS: $(uname -s)" >&2; exit 1 ;;
  esac
fi

case "$MODE" in
  release) OPT_FLAGS=(-O2) ;;
  debug) OPT_FLAGS=(-O0 -g -D_DEBUG) ;;
  *) echo "Unsupported MODE: $MODE. Use MODE=release or MODE=debug." >&2; exit 1 ;;
esac

BUILD_DIR="$ROOT_DIR/build/$TARGET"
OBJ_DIR="$BUILD_DIR/obj"
RAYLIB_DIR="$ROOT_DIR/src/vendor/raylib/src"
GLFW_INCLUDE="$RAYLIB_DIR/external/glfw/include"
EXE="$BUILD_DIR/$APP_NAME"

mkdir -p "$OBJ_DIR"

APP_SOURCES=(
  "$ROOT_DIR/src/main.c"
  "$ROOT_DIR/src/native_dialog.c"
  "$ROOT_DIR/src/png_text.c"
)

RAYLIB_SOURCES=(
  "$RAYLIB_DIR/rcore.c"
  "$RAYLIB_DIR/rshapes.c"
  "$RAYLIB_DIR/rtextures.c"
  "$RAYLIB_DIR/rtext.c"
  "$RAYLIB_DIR/rmodels.c"
  "$RAYLIB_DIR/utils.c"
  "$RAYLIB_DIR/raudio.c"
  "$RAYLIB_DIR/rglfw.c"
)

COMMON_CFLAGS=(
  -Wall
  -DPLATFORM_DESKTOP_GLFW
  -DGRAPHICS_API_OPENGL_33
  -I"$RAYLIB_DIR"
  -I"$GLFW_INCLUDE"
  "${OPT_FLAGS[@]}"
)

APP_CFLAGS=(-std=c11 -Wextra -Wpedantic)
RAYLIB_CFLAGS=(-std=c99 -Wno-missing-braces -Werror=pointer-arith -fno-strict-aliasing)
LDFLAGS=()

case "$TARGET" in
  linux)
    : "${CC:=cc}"
    COMMON_CFLAGS+=(-D_GNU_SOURCE -D_GLFW_X11 -fPIC)
    LDFLAGS+=(-lGL -lm -lpthread -ldl -lrt -lX11)
    ;;
  windows)
    : "${CC:=x86_64-w64-mingw32-gcc}"
    EXE="$BUILD_DIR/$APP_NAME.exe"
    LDFLAGS+=(-static-libgcc -lopengl32 -lgdi32 -lwinmm -lshell32 -lcomdlg32 -lm)
    ;;
  macos)
    if [ "$(uname -s)" != "Darwin" ]; then
      echo "macOS builds must run on macOS with Xcode Command Line Tools." >&2
      exit 1
    fi
    : "${CC:=clang}"
    LDFLAGS+=(-framework OpenGL -framework Cocoa -framework IOKit -framework CoreAudio -framework CoreVideo -lm)
    ;;
  *)
    echo "Unsupported target: $TARGET. Use linux, windows, macos, or host." >&2
    exit 1
    ;;
esac

if ! command -v "$CC" >/dev/null 2>&1; then
  echo "C compiler not found: $CC" >&2
  exit 1
fi

object_path() {
  local source="$1"
  local rel="${source#$ROOT_DIR/}"
  rel="${rel//\//_}"
  printf '%s/%s.o' "$OBJ_DIR" "$rel"
}

compile_source() {
  local source="$1"
  local kind="$2"
  local obj
  obj="$(object_path "$source")"

  local flags=("${COMMON_CFLAGS[@]}")
  if [ "$kind" = "app" ]; then
    flags+=("${APP_CFLAGS[@]}")
  else
    flags+=("${RAYLIB_CFLAGS[@]}")
  fi

  if [ "$TARGET" = "macos" ] && [ "$(basename "$source")" = "rglfw.c" ]; then
    flags+=(-x objective-c)
  fi

  echo "CC ${source#$ROOT_DIR/}"
  "$CC" -c "$source" -o "$obj" "${flags[@]}" ${CFLAGS:-}
  OBJECTS+=("$obj")
}

OBJECTS=()
for source in "${APP_SOURCES[@]}"; do
  compile_source "$source" app
done
for source in "${RAYLIB_SOURCES[@]}"; do
  compile_source "$source" raylib
done

echo "LD ${EXE#$ROOT_DIR/}"
"$CC" -o "$EXE" "${OBJECTS[@]}" "${LDFLAGS[@]}" ${LDFLAGS_EXTRA:-}

echo "$EXE"
