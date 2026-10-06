#!/usr/bin/env bash
# Build a release binary then produce a distributable for the host platform,
# placed flat in build/ with a full, unique name (per AGENTS.md).
#   Linux  -> build/linux-png-editor-slint-<arch>.deb   (dpkg-deb)
#   macOS  -> build/macos-png-editor-slint-<arch>.dmg    (create-dmg)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "❌ Error: sourced script. Please launch new process"
  return 1 2>/dev/null || exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$ROOT_DIR/build"
BIN_NAME="png-editor-slint"
APP_ID="com.gui_survey.png-editor-slint"
VERSION="0.1.0"
[[ -s "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

"$SCRIPT_DIR/build.sh" release
BIN="$ROOT_DIR/target/release/$BIN_NAME"

case "$(uname -m)" in
  x86_64|amd64)   ARCH="x86_64"; DEB_ARCH="amd64" ;;
  aarch64|arm64)  ARCH="arm64";  DEB_ARCH="arm64" ;;
  *) ARCH="$(uname -m)"; DEB_ARCH="$ARCH" ;;
esac

mkdir -p "$OUT_DIR"

case "$(uname -s)" in
  Linux)
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    install -Dm755 "$BIN" "$STAGE/usr/bin/$BIN_NAME"
    install -Dm644 /dev/stdin "$STAGE/usr/share/applications/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=PNG Editor (slint)
Exec=$BIN_NAME
Categories=Graphics;
Terminal=false
EOF
    mkdir -p "$STAGE/DEBIAN"
    cat > "$STAGE/DEBIAN/control" <<EOF
Package: png-editor-slint
Version: $VERSION
Section: graphics
Priority: optional
Architecture: $DEB_ARCH
Maintainer: gui_survey <noreply@local>
Description: Desktop PNG editor built with iced (Rust).
EOF
    DEST="$OUT_DIR/linux-png-editor-slint-${ARCH}.deb"
    dpkg-deb --build --root-owner-group "$STAGE" "$DEST"
    echo "$DEST"
    ;;
  Darwin)
    APP="$OUT_DIR/PNG Editor (slint).app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"
    cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PNG Editor (slint)</string>
  <key>CFBundleIdentifier</key><string>$APP_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$BIN_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
    # Sign + notarize here (requires Apple Developer credentials — not possible
    # in the Linux CI container). Example:
    #   codesign --deep --force --options runtime --sign "$DEV_ID" "$APP"
    #   xcrun notarytool submit ... && xcrun stapler staple "$APP"
    DEST="$OUT_DIR/macos-png-editor-slint-${ARCH}.dmg"
    if command -v create-dmg >/dev/null 2>&1; then
      rm -f "$DEST"
      create-dmg --volname "PNG Editor (slint)" "$DEST" "$APP" || hdiutil create -volname "PNG Editor (slint)" -srcfolder "$APP" -ov -format UDZO "$DEST"
    else
      hdiutil create -volname "PNG Editor (slint)" -srcfolder "$APP" -ov -format UDZO "$DEST"
    fi
    echo "$DEST"
    ;;
  *)
    echo "Unsupported host OS for packaging: $(uname -s)" >&2
    exit 1
    ;;
esac
