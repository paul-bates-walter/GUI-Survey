//! Host shell for the egui PNG editor.
//!
//! This binary is deliberately thin: it owns the window/event loop and the
//! `AppState`, and every frame it calls the app's `draw` through the
//! hot-reloadable dylib (src/lib.rs). Because the state lives here in the host
//! and only the dylib is rebuilt on a source change, edits appear in the running
//! app with the picture, tool, and metadata all preserved — genuine in-process
//! hot reload (spec.md "Hot Swapping"), not a rebuild-and-restart. See
//! scripts/watch.sh for the rebuild loop that drives it.

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::path::{Path, PathBuf};
use std::time::SystemTime;

use eframe::egui;
use png_editor_egui::{new_app_state, AppState};

/// The dylib's exported entry point (see `hot_draw` in src/lib.rs).
type DrawFn = unsafe extern "C" fn(*mut AppState, *const egui::Context);

/// Watches the app dylib and reloads it in place when it is rebuilt.
struct Reloader {
    /// The dylib cargo produces next to the binary, e.g.
    /// `target/debug/libpng_editor_egui.so`. `None` in a build without it, in
    /// which case we fall back to the statically linked `draw`.
    source: Option<PathBuf>,
    /// Every dylib we have dlopen'd (we load a copy so cargo can overwrite the
    /// original while we hold a handle). We never unload one: state egui built
    /// through the old code (e.g. a TextureHandle) can outlive a reload, and
    /// unmapping the code it points at would crash on its eventual drop.
    /// Retaining the mappings costs a little address space per reload (dev-only).
    libs: Vec<libloading::Library>,
    /// mtime of `source` at the last (re)load, to detect rebuilds.
    loaded_at: Option<SystemTime>,
    /// Unique suffix for each live copy so dlopen doesn't return a cached image.
    generation: u64,
    /// The draw function currently in effect (dylib symbol, or static fallback).
    draw: DrawFn,
}

impl Reloader {
    fn new() -> Self {
        let source = dylib_path().filter(|p| p.exists());
        let mut r = Reloader {
            source,
            libs: Vec::new(),
            loaded_at: None,
            generation: 0,
            // Fallback: the copy linked into this binary. Used until (and if) a
            // dylib loads, and whenever a reload fails to build cleanly.
            draw: png_editor_egui::hot_draw as DrawFn,
        };
        r.try_reload();
        r
    }

    /// If the dylib on disk is newer than what we loaded, swap it in.
    fn reload_if_changed(&mut self) {
        let Some(src) = &self.source else { return };
        let Ok(mtime) = std::fs::metadata(src).and_then(|m| m.modified()) else {
            return;
        };
        if self.loaded_at != Some(mtime) {
            self.try_reload();
        }
    }

    fn try_reload(&mut self) {
        let Some(src) = self.source.clone() else { return };
        let Ok(meta) = std::fs::metadata(&src) else { return };
        let Ok(mtime) = meta.modified() else { return };

        // Load a private copy so a concurrent `cargo build --lib` can replace the
        // original, and so each dlopen sees a distinct path (not a cached image).
        self.generation += 1;
        let live = std::env::temp_dir().join(format!(
            "png-editor-egui-hot-{}-{}.so",
            std::process::id(),
            self.generation
        ));
        if std::fs::copy(&src, &live).is_err() {
            return; // keep the current draw fn
        }

        match unsafe { load_draw(&live) } {
            Ok((lib, draw)) => {
                self.draw = draw;
                // Retain (never unload) the library — see `libs` docs.
                self.libs.push(lib);
                self.loaded_at = Some(mtime);
                let _ = std::fs::remove_file(&live); // dlopen has mapped it already
                eprintln!("↻ hot-reloaded {}", src.display());
            }
            Err(e) => {
                let _ = std::fs::remove_file(&live);
                eprintln!("✗ hot reload failed ({e}); keeping running code");
            }
        }
    }
}

/// dlopen `path` and resolve the `hot_draw` symbol. The returned `DrawFn` points
/// into `Library`, which the caller must keep alive while the pointer is used.
unsafe fn load_draw(path: &Path) -> Result<(libloading::Library, DrawFn), libloading::Error> {
    let lib = libloading::Library::new(path)?;
    let sym: libloading::Symbol<DrawFn> = lib.get(b"hot_draw")?;
    let f = *sym;
    Ok((lib, f))
}

/// Path to the app dylib cargo emits next to the running executable.
fn dylib_path() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let dir = exe.parent()?;
    let name = if cfg!(target_os = "windows") {
        "png_editor_egui.dll"
    } else if cfg!(target_os = "macos") {
        "libpng_editor_egui.dylib"
    } else {
        "libpng_editor_egui.so"
    };
    Some(dir.join(name))
}

struct HostApp {
    state: AppState,
    reloader: Reloader,
}

impl eframe::App for HostApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.reloader.reload_if_changed();
        // SAFETY: `state` is a live AppState built by this binary; the dylib was
        // compiled from the same crate so its AppState layout matches.
        unsafe { (self.reloader.draw)(&mut self.state as *mut AppState, ctx as *const egui::Context) };
        // Poll continuously so a rebuild is picked up without needing input.
        ctx.request_repaint();
    }
}

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        renderer: eframe::Renderer::Wgpu,
        viewport: egui::ViewportBuilder::default().with_inner_size([1100.0, 720.0]),
        ..Default::default()
    };
    eframe::run_native(
        "PNG Editor — egui",
        options,
        Box::new(|_cc| {
            Ok(Box::new(HostApp {
                state: new_app_state(),
                reloader: Reloader::new(),
            }) as Box<dyn eframe::App>)
        }),
    )
}
