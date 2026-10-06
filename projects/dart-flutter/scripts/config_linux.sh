export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && sudo apt-get install -y \
  clang \
  cmake \
  curl \
  git \
  libglu1-mesa \
  libgtk-3-dev \
  liblzma-dev \
  libstdc++-12-dev \
  ninja-build \
  pkg-config \
  unzip \
  xz-utils \
  zip \
  dpkg-dev

if [[ ! -x "$FLUTTER_HOME/bin/flutter" ]]; then
  ARCHIVE="/tmp/flutter-$FLUTTER_VERSION.tar.xz"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o "$ARCHIVE"
  $SUDO rm -rf "$FLUTTER_HOME"
  $SUDO tar -xf "$ARCHIVE" -C "$(dirname "$FLUTTER_HOME")"
  rm "$ARCHIVE"
  $SUDO chown -R "$(id -u):$(id -g)" "$FLUTTER_HOME"
fi

sudo ln -sf "$FLUTTER_HOME/bin/flutter" /usr/local/bin/flutter
sudo ln -sf "$FLUTTER_HOME/bin/dart" /usr/local/bin/dart

flutter config --enable-linux-desktop
flutter create --platforms=linux --project-name gui_survey_flutter .
flutter pub get
echo "config_linux done"
