//! Host shell for the Slint PNG editor.
//!
//! Thin wiring only: it creates the `AppWindow` and the `AppState`, then asks the
//! hot-reloadable app dylib (src/lib.rs) to wire the UI callbacks via `install`.
//! A repeating Slint timer watches the dylib and, when scripts/watch.sh rebuilds
//! it, reloads the .so and re-runs `install` — replacing the callback closures on
//! the live window with the new code. The window and models are host-owned, so
//! the picture and metadata form survive the swap: genuine in-process hot reload
//! (spec.md "Hot Swapping"), not a rebuild-and-restart.

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::{Duration, SystemTime};

use slint::{ComponentHandle, TimerMode, VecModel};

use png_editor_slint::{new_model, new_state, AppState, AppWindow, MetaRow};

// Plain Rust ABI (matches the `#[no_mangle]` wrapper in src/lib.rs): host and
// dylib are always built by the same rustc, so the signature lines up.
type InstallFn = fn(&AppWindow, &Rc<RefCell<AppState>>, &Rc<VecModel<MetaRow>>);

struct Reloader {
    source: Option<PathBuf>,
    /// Every dylib we have loaded. Never unloaded: the callback closures Slint
    /// holds (and any Slint objects the old code built) point into a library's
    /// code, so unmapping it would crash on their eventual drop. Retaining the
    /// mappings costs a little address space per reload (dev-only).
    libs: Vec<libloading::Library>,
    loaded_at: Option<SystemTime>,
    generation: u64,
    install: InstallFn,
}

impl Reloader {
    fn new() -> Self {
        let mut r = Reloader {
            source: dylib_path().filter(|p| p.exists()),
            libs: Vec::new(),
            loaded_at: None,
            generation: 0,
            // Fallback: the copy linked into this binary, used until a dylib loads
            // and whenever a reload fails to build cleanly.
            install: png_editor_slint::hot_install,
        };
        r.try_reload();
        r
    }

    /// Returns true if a newer dylib was just swapped in (so the caller re-wires).
    fn reload_if_changed(&mut self) -> bool {
        let Some(src) = &self.source else { return false };
        let Ok(mtime) = std::fs::metadata(src).and_then(|m| m.modified()) else {
            return false;
        };
        if self.loaded_at != Some(mtime) {
            self.try_reload()
        } else {
            false
        }
    }

    fn try_reload(&mut self) -> bool {
        let Some(src) = self.source.clone() else { return false };
        let Ok(mtime) = std::fs::metadata(&src).and_then(|m| m.modified()) else {
            return false;
        };

        self.generation += 1;
        let live = std::env::temp_dir().join(format!(
            "png-editor-slint-hot-{}-{}.so",
            std::process::id(),
            self.generation
        ));
        if std::fs::copy(&src, &live).is_err() {
            return false;
        }

        match unsafe { load_install(&live) } {
            Ok((lib, install)) => {
                self.install = install;
                self.libs.push(lib); // retain (never unload) — see `libs` docs
                self.loaded_at = Some(mtime);
                let _ = std::fs::remove_file(&live);
                eprintln!("↻ hot-reloaded {}", src.display());
                true
            }
            Err(e) => {
                let _ = std::fs::remove_file(&live);
                eprintln!("✗ hot reload failed ({e}); keeping running code");
                false
            }
        }
    }
}

unsafe fn load_install(path: &Path) -> Result<(libloading::Library, InstallFn), libloading::Error> {
    let lib = libloading::Library::new(path)?;
    let install = *lib.get::<InstallFn>(b"hot_install")?;
    Ok((lib, install))
}

fn dylib_path() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    let dir = exe.parent()?;
    let name = if cfg!(target_os = "windows") {
        "png_editor_slint.dll"
    } else if cfg!(target_os = "macos") {
        "libpng_editor_slint.dylib"
    } else {
        "libpng_editor_slint.so"
    };
    Some(dir.join(name))
}

fn main() -> Result<(), slint::PlatformError> {
    let ui = AppWindow::new()?;
    let state = new_state();
    let model = new_model();

    let reloader = Rc::new(RefCell::new(Reloader::new()));

    // Initial wiring through the (possibly hot-loaded) dylib.
    (reloader.borrow().install)(&ui, &state, &model);

    // Poll the dylib on the UI thread; re-wire the callbacks when it is rebuilt.
    let timer = slint::Timer::default();
    {
        let (rl, ui_weak, st, md) = (reloader.clone(), ui.as_weak(), state.clone(), model.clone());
        timer.start(TimerMode::Repeated, Duration::from_millis(200), move || {
            let Some(ui) = ui_weak.upgrade() else { return };
            let mut rl = rl.borrow_mut();
            if rl.reload_if_changed() {
                (rl.install)(&ui, &st, &md);
            }
        });
    }

    ui.run()
}
