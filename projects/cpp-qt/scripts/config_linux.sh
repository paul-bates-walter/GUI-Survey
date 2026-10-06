export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && sudo apt-get install -y \
  build-essential \
  cmake \
  ninja-build \
  qt6-base-dev \
  qt6-base-dev-tools \
  libgl1-mesa-dev \
  dpkg-dev \
  file \
  inotify-tools