# SDL + Zig PNG editor

Native Zig implementation of the survey PNG editor using SDL3 for the window,
input, rendering, and file dialogs. PNG load/save uses SDL_image, the SDL
companion image library.

## Build

Install Zig, SDL3 development files, and SDL3_image development files, then run:

```sh
zig build
zig build run
```

This sample expects SDL 3.2 or newer so `SDL_ShowOpenFileDialog` and
`SDL_ShowSaveFileDialog` are available.
