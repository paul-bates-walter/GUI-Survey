if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="png-editor-sdl-zig"
. "$SCRIPT_DIR/_sdl-env.sh"

bash "$SCRIPT_DIR/build.sh" release

case "$(uname -m)" in
  x86_64|amd64)   ARCH="x86_64"; DEB_ARCH="amd64" ;;
  aarch64|arm64)  ARCH="arm64";  DEB_ARCH="arm64" ;;
  *) ARCH="$(uname -m)"; DEB_ARCH="$ARCH" ;;
esac

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "package.sh currently supports Linux only" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/usr/lib/$APP_NAME" "$STAGE/usr/bin" "$STAGE/DEBIAN" \
  "$STAGE/usr/share/applications"
chmod 0755 "$STAGE" "$STAGE/DEBIAN"

install -m755 "$ROOT_DIR/zig-out/bin/$APP_NAME" "$STAGE/usr/lib/$APP_NAME/$APP_NAME"
cp -P "$SDL_PREFIX"/lib/libSDL3.so* "$STAGE/usr/lib/$APP_NAME/"
cp -P "$SDL_PREFIX"/lib/libSDL3_image.so* "$STAGE/usr/lib/$APP_NAME/"

cat > "$STAGE/usr/bin/$APP_NAME" <<EOF
LD_LIBRARY_PATH="/usr/lib/$APP_NAME\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" exec "/usr/lib/$APP_NAME/$APP_NAME" "\$@"
EOF
chmod 0755 "$STAGE/usr/bin/$APP_NAME"

cat > "$STAGE/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PNG Editor (SDL + Zig)
Exec=$APP_NAME
Categories=Graphics;
Terminal=false
EOF

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: 0.1.0
Section: graphics
Priority: optional
Architecture: $DEB_ARCH
Maintainer: gui_survey <noreply@local>
Description: Desktop PNG editor built with SDL3 (Zig).
EOF

mkdir -p "$ROOT_DIR/build"
DEST="$ROOT_DIR/build/linux-$APP_NAME-$ARCH.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$DEST"
echo "$DEST"
