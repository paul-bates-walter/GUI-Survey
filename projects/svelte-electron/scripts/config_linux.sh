export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && sudo apt-get install -y \
  curl \
  libnspr4 \
  libnss3 \
  fakeroot \
  dpkg-dev

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install 24
nvm use 24

cd "$(dirname "${BASH_SOURCE[0]}")/.."
npm install
npm audit fix
