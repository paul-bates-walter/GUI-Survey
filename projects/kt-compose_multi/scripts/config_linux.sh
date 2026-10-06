export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && sudo apt-get install -y \
  openjdk-17-jdk \
  gradle \
  fakeroot \
  dpkg-dev \
  binutils \
  inotify-tools