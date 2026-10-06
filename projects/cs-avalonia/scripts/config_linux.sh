export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && apt-get install -y \
  dotnet-sdk-10.0 \
  dpkg-dev \
  xvfb \
  libx11-6 \
  libice6 \
  libsm6 \
  libfontconfig1 \
  fontconfig

export DOTNET_CLI_TELEMETRY_OPTOUT=1