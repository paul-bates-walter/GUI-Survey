#!/usr/bin/env bash
set -euo pipefail

APP_NAME="png-editor-raylib"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="${1:-host}"

if [ "$TARGET" = "host" ]; then
  case "$(uname -s)" in
    Linux) TARGET="linux" ;;
    Darwin) TARGET="macos" ;;
    *) echo "Unsupported host OS: $(uname -s)" >&2; exit 1 ;;
  esac
fi

"$SCRIPT_DIR/build.sh" "$TARGET"

case "$(uname -m)" in
  x86_64|amd64)   HOST_ARCH="x86_64"; DEB_ARCH="amd64" ;;
  aarch64|arm64)  HOST_ARCH="arm64";  DEB_ARCH="arm64" ;;
  *) HOST_ARCH="$(uname -m)"; DEB_ARCH="$HOST_ARCH" ;;
esac

case "$TARGET" in
  linux)
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    install -Dm755 "$ROOT_DIR/build/linux/$APP_NAME" "$STAGE/usr/bin/$APP_NAME"
    install -Dm644 /dev/stdin "$STAGE/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PNG Editor (raylib)
Exec=$APP_NAME
Categories=Graphics;
Terminal=false
EOF
    mkdir -p "$STAGE/DEBIAN"
    chmod 0755 "$STAGE" "$STAGE/DEBIAN"
    cat > "$STAGE/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: 0.1.0
Section: graphics
Priority: optional
Architecture: $DEB_ARCH
Maintainer: gui_survey <noreply@local>
Description: Desktop PNG editor built with raylib (C).
EOF
    package="$ROOT_DIR/build/linux-$APP_NAME-$HOST_ARCH.deb"
    dpkg-deb --build --root-owner-group "$STAGE" "$package"
    ;;
  windows)
    package="$ROOT_DIR/build/windows-$APP_NAME-x86_64.zip"
    rm -f "$package"
    (cd "$ROOT_DIR/build/windows" && zip -q "$package" "$APP_NAME.exe")
    ;;
  macos)
    app_dir="$ROOT_DIR/build/macos/$APP_NAME.app"
    contents="$app_dir/Contents"
    mkdir -p "$contents/MacOS"
    cp "$ROOT_DIR/build/macos/$APP_NAME" "$contents/MacOS/$APP_NAME"
    cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>local.desktop-gui-survey.$APP_NAME</string>
  <key>CFBundleName</key>
  <string>PNG Editor raylib</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
</dict>
</plist>
PLIST
    package="$ROOT_DIR/build/macos-$APP_NAME-$HOST_ARCH.zip"
    rm -f "$package"
    (cd "$ROOT_DIR/build/macos" && zip -qr "$package" "$APP_NAME.app")
    ;;
  *)
    echo "Unsupported target: $TARGET" >&2
    exit 1
    ;;
esac

echo "$package"
