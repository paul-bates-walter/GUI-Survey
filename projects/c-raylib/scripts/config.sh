#!/usr/bin/env sh
set -eu

OS_NAME="$(uname -s)"

case "$OS_NAME" in
  Linux)
    if [ "$(id -u)" -eq 0 ]; then
      SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      echo "This script needs root privileges or sudo to install apt packages." >&2
      exit 1
    fi

    export DEBIAN_FRONTEND=noninteractive

    $SUDO apt-get update
    $SUDO apt-get install -y \
      clang \
      gcc-mingw-w64-x86-64 \
      libc6-dev \
      libasound2-dev \
      libgl1-mesa-dev \
      libx11-dev \
      libxcursor-dev \
      libxi-dev \
      libxinerama-dev \
      libxrandr-dev \
      pkg-config \
      zip
    ;;
  Darwin)
    if ! xcode-select -p >/dev/null 2>&1; then
      echo "Xcode Command Line Tools are required for macOS builds." >&2
      echo "Run 'xcode-select --install', complete the installer, then rerun this script." >&2
      exit 1
    fi

    for tool in clang zip; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required macOS build tool is missing: $tool" >&2
        echo "Run 'xcode-select --install', complete the installer, then rerun this script." >&2
        exit 1
      fi
    done

    echo "macOS build dependencies are available."
    ;;
  *)
    echo "Unsupported operating system for config.sh: $OS_NAME" >&2
    exit 1
    ;;
esac
