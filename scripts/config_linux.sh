root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

f=0
bash "$root/projects/avalonia-cs/scripts/config_linux.sh" || f=1
bash "$root/projects/compose_multi-kt/scripts/config_linux.sh" || f=1
bash "$root/projects/egui-rs/scripts/config_linux.sh" || f=1
bash "$root/projects/electron-vite-svelte/scripts/config_linux.sh" || f=1
bash "$root/projects/flutter-dart/scripts/config_linux.sh" || f=1
bash "$root/projects/iced-rs/scripts/config_linux.sh" || f=1
bash "$root/projects/qt-cpp/scripts/config_linux.sh" || f=1
bash "$root/projects/sdl-zig/scripts/config_linux.sh" || f=1
bash "$root/projects/tauri-rs/scripts/config_linux.sh" || f=1
bash "$root/projects/wxWidgets-cpp/scripts/config_linux.sh" || f=1
exit $f
