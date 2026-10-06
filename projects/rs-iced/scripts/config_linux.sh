export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && apt-get install -y \
  build-essential \
  curl \
  pkg-config \
  cmake \
  dpkg-dev \
  file \
  inotify-tools \
  libx11-dev \
  libxkbcommon-dev \
  libxkbcommon-x11-dev \
  libwayland-dev \
  libxcb1-dev \
  libvulkan1 \
  mesa-vulkan-drivers \
  libgl1-mesa-dri \
  libgl1 \
  libglx-mesa0 \
  libegl1 \
  libegl-mesa0 \
  libfontconfig1-dev \
  libfreetype6-dev

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "${HOME}/.cargo/env"

# going to need something to create .deb, .exe, .app
cargo install cross
cargo install cargo-packager --locked

