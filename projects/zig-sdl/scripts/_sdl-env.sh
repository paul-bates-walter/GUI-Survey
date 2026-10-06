SDL_PREFIX="${SDL_PREFIX:-/opt/sdl3}"
if [[ -d "$SDL_PREFIX/lib/pkgconfig" ]]; then
  export PKG_CONFIG_PATH="$SDL_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  export LD_LIBRARY_PATH="$SDL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
