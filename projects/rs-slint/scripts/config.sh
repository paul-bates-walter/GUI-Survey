#!/usr/bin/env sh
# Idempotent setup for the slint-rs implementation.
# Installs the Rust toolchain plus the Linux system libraries iced/winit need.
#
# NOTE (repo rule: no autonomous internet): rustup and `cargo build` fetch from
# the network. This script is the human-run, internet-touching setup step.
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
    # Build tools + the wgpu/winit runtime stack (Vulkan/GL, X11 + Wayland,
    # fontconfig) and .deb tooling.
    $SUDO apt-get install -y \
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
    ;;
  Darwin)
    if ! command -v brew >/dev/null 2>&1; then
      echo "Homebrew is required on macOS. Install from https://brew.sh then rerun." >&2
      exit 1
    fi
    brew install cmake create-dmg
    ;;
  *)
    echo "Unsupported operating system for config.sh: $OS_NAME" >&2
    exit 1
    ;;
esac

# Rust toolchain (internet).
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
if [ -x "$HOME/.cargo/bin/cargo" ] && [ "$(id -u)" -ne 0 ]; then
  # Make cargo/rustc visible to non-login shells.
  echo "Add \$HOME/.cargo/bin to PATH (e.g. . \"$HOME/.cargo/env\")." >&2
fi

# cargo-watch powers the live-reload script; harmless if already present.
if command -v cargo >/dev/null 2>&1 && ! cargo watch --version >/dev/null 2>&1; then
  cargo install cargo-watch || echo "cargo-watch install skipped (optional)." >&2
fi

echo "Setup complete. Build with scripts/build.sh"
