export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && apgt-get install -y \
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
  libgl1-mesa-glx \
  libegl1-mesa \
  libfontconfig1-dev \
  libfreetype6-dev

# install rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y