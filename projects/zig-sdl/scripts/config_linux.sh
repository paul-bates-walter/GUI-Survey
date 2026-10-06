if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

ZIG_VERSION="${ZIG_VERSION:-0.13.0}"
ZIG_HOME="${ZIG_HOME:-/opt/zig}"
SDL_PREFIX="${SDL_PREFIX:-/opt/sdl3}"
SDL_VERSION="${SDL_VERSION:-3.2.18}"
SDL_IMAGE_VERSION="${SDL_IMAGE_VERSION:-3.2.4}"

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  echo "needs root or sudo for installs" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update
$SUDO apt-get install -y \
  build-essential cmake ninja-build git curl xz-utils pkg-config dpkg-dev \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxinerama-dev \
  libxi-dev libxss-dev libwayland-dev libxkbcommon-dev libdecor-0-dev \
  libegl1-mesa-dev libgl1-mesa-dev libasound2-dev libpulse-dev \
  libdbus-1-dev libudev-dev libdrm-dev libgbm-dev

case "$(uname -m)" in
  x86_64|amd64)  ZIG_ARCH="x86_64" ;;
  aarch64|arm64) ZIG_ARCH="aarch64" ;;
  *) echo "unsupported arch for zig install: $(uname -m)" >&2; exit 1 ;;
esac

if [[ ! -x "$ZIG_HOME/zig" ]]; then
  ARCHIVE="/tmp/zig-$ZIG_VERSION.tar.xz"
  curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-linux-$ZIG_ARCH-$ZIG_VERSION.tar.xz" -o "$ARCHIVE"
  $SUDO rm -rf "$ZIG_HOME"
  $SUDO mkdir -p "$ZIG_HOME"
  $SUDO tar -xf "$ARCHIVE" -C "$ZIG_HOME" --strip-components=1
  rm "$ARCHIVE"
fi
$SUDO ln -sf "$ZIG_HOME/zig" /usr/local/bin/zig

if [[ ! -f "$SDL_PREFIX/lib/pkgconfig/sdl3.pc" ]]; then
  SRC="$(mktemp -d)"
  curl -fsSL "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL3-$SDL_VERSION.tar.gz" | tar -xz -C "$SRC"
  cmake -S "$SRC/SDL3-$SDL_VERSION" -B "$SRC/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SDL_PREFIX" \
    -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
  cmake --build "$SRC/build"
  $SUDO cmake --install "$SRC/build"
  rm -rf "$SRC"
fi

if [[ ! -f "$SDL_PREFIX/lib/pkgconfig/sdl3-image.pc" ]]; then
  SRC="$(mktemp -d)"
  curl -fsSL "https://github.com/libsdl-org/SDL_image/releases/download/release-$SDL_IMAGE_VERSION/SDL3_image-$SDL_IMAGE_VERSION.tar.gz" | tar -xz -C "$SRC"
  cmake -S "$SRC/SDL3_image-$SDL_IMAGE_VERSION" -B "$SRC/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SDL_PREFIX" \
    -DCMAKE_PREFIX_PATH="$SDL_PREFIX" \
    -DSDLIMAGE_SAMPLES=OFF -DSDLIMAGE_TESTS=OFF
  cmake --build "$SRC/build"
  $SUDO cmake --install "$SRC/build"
  rm -rf "$SRC"
fi

echo "config_linux done"
